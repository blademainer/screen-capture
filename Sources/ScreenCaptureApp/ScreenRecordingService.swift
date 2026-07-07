import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia

enum RecordingMode: Equatable {
    case fullScreen
    case selectedArea(CGRect)

    var userFacingName: String {
        switch self {
        case .fullScreen:
            return "Full Screen Recording"
        case .selectedArea:
            return "Area Recording"
        }
    }

    var isSelectedArea: Bool {
        if case .selectedArea = self {
            return true
        }
        return false
    }
}

@MainActor
protocol ScreenRecordingServiceDelegate: AnyObject {
    func recordingServiceDidStart(_ service: ScreenRecordingService, outputURL: URL)
    func recordingService(_ service: ScreenRecordingService, didFinishWith result: Result<URL, Error>)
}

@MainActor
final class ScreenRecordingService {
    weak var delegate: ScreenRecordingServiceDelegate?

    private let preferences: AppPreferences
    private var recorder: ScreenCaptureRecorder?
    private var outputURL: URL?
    private var startupTask: Task<Void, Never>?
    private(set) var isStarting = false
    private(set) var mode: RecordingMode?
    private(set) var startedAt: Date?

    var isRecording: Bool {
        recorder != nil || isStarting
    }

    init(preferences: AppPreferences = .shared) {
        self.preferences = preferences
    }

    func start(mode: RecordingMode) {
        guard recorder == nil, !isStarting else {
            delegate?.recordingService(self, didFinishWith: .failure(CaptureError.recorderAlreadyRunning))
            return
        }

        isStarting = true
        self.mode = mode

        startupTask = Task {
            do {
                let directory = preferences.outputDirectory
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let outputURL = FileNamer.outputURL(kind: .recording, directory: directory, extension: "mov")
                let recorder = try ScreenCaptureRecorder.make(
                    mode: mode,
                    outputURL: outputURL,
                    showCursor: preferences.showCursor,
                    showClicks: preferences.showRecordingClicks
                )

                try await recorder.start()
                self.isStarting = false
                self.startupTask = nil
                self.recorder = recorder
                self.outputURL = outputURL
                self.mode = mode
                self.startedAt = Date()
                delegate?.recordingServiceDidStart(self, outputURL: outputURL)
            } catch {
                self.isStarting = false
                self.startupTask = nil
                self.recorder = nil
                self.outputURL = nil
                self.mode = nil
                self.startedAt = nil
                delegate?.recordingService(self, didFinishWith: .failure(error))
            }
        }
    }

    func stop() {
        if isStarting, recorder == nil {
            startupTask?.cancel()
            startupTask = nil
            isStarting = false
            mode = nil
            delegate?.recordingService(self, didFinishWith: .failure(CaptureError.cancelled))
            return
        }

        guard let recorder, let outputURL else {
            delegate?.recordingService(self, didFinishWith: .failure(CaptureError.recorderNotRunning))
            return
        }

        self.recorder = nil
        self.outputURL = nil
        self.startupTask = nil
        self.isStarting = false
        self.mode = nil
        self.startedAt = nil

        Task {
            do {
                try await recorder.stop()
                delegate?.recordingService(self, didFinishWith: .success(outputURL))
            } catch {
                delegate?.recordingService(self, didFinishWith: .failure(error))
            }
        }
    }
}

@MainActor
enum RecordingDiagnostics {
    static func displayCount() -> Int {
        NSScreen.screens.count
    }

    static func recordFullScreen(outputURL: URL, duration: TimeInterval) async throws {
        let recorder = try ScreenCaptureRecorder.make(mode: .fullScreen, outputURL: outputURL, showCursor: true, showClicks: false)
        try await recorder.start()
        try await Task.sleep(nanoseconds: UInt64(max(0.5, duration) * 1_000_000_000))
        try await recorder.stop()
    }

    static func recordSelectedArea(outputURL: URL, duration: TimeInterval) async throws {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            throw CaptureError.noDisplay
        }

        let width = min(screen.frame.width * 0.5, 640)
        let height = min(screen.frame.height * 0.5, 360)
        let rect = CGRect(x: screen.frame.midX - width / 2, y: screen.frame.midY - height / 2, width: width, height: height)
        let recorder = try ScreenCaptureRecorder.make(mode: .selectedArea(rect), outputURL: outputURL, showCursor: true, showClicks: false)
        try await recorder.start()
        try await Task.sleep(nanoseconds: UInt64(max(0.5, duration) * 1_000_000_000))
        try await recorder.stop()
    }
}

private final class ScreenCaptureRecorder: @unchecked Sendable {
    private let outputURL: URL
    private let displayID: CGDirectDisplayID
    private let displayFrame: CGRect
    private let captureRectPixels: CGRect
    private let outputSize: CGSize
    private let showCursor: Bool
    private let showClicks: Bool
    private let frameRate: Int32 = 15
    private let queue = DispatchQueue(label: "ScreenCapture.frame-recorder")
    private let lock = NSLock()

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var timer: DispatchSourceTimer?
    private var frameIndex: Int64 = 0
    private var isRecording = false

    private init(outputURL: URL, displayID: CGDirectDisplayID, displayFrame: CGRect, captureRectPixels: CGRect, showCursor: Bool, showClicks: Bool) {
        self.outputURL = outputURL
        self.displayID = displayID
        self.displayFrame = displayFrame
        self.captureRectPixels = captureRectPixels.integral
        self.outputSize = CGSize(width: max(2, captureRectPixels.width.rounded()), height: max(2, captureRectPixels.height.rounded()))
        self.showCursor = showCursor
        self.showClicks = showClicks
    }

    @MainActor
    static func make(mode: RecordingMode, outputURL: URL, showCursor: Bool, showClicks: Bool) throws -> ScreenCaptureRecorder {
        guard let screen = screen(for: mode),
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            throw CaptureError.noDisplay
        }

        let scale = screen.backingScaleFactor
        let captureRectPixels: CGRect
        switch mode {
        case .fullScreen:
            let bounds = CGDisplayBounds(displayID)
            captureRectPixels = CGRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale)
        case .selectedArea(let rect):
            captureRectPixels = pixelRect(for: rect, in: screen)
        }

        guard captureRectPixels.width >= 2, captureRectPixels.height >= 2 else {
            throw CaptureError.cancelled
        }

        return ScreenCaptureRecorder(
            outputURL: outputURL,
            displayID: displayID,
            displayFrame: screen.frame,
            captureRectPixels: captureRectPixels,
            showCursor: showCursor,
            showClicks: showClicks
        )
    }

    func start() async throws {
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(2_000_000, Int(outputSize.width * outputSize.height * 2))
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw CaptureError.cannotCreateOutput
        }
        writer.add(input)

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(outputSize.width),
            kCVPixelBufferHeightKey as String: Int(outputSize.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)

        guard writer.startWriting() else {
            throw writer.error ?? CaptureError.cannotCreateOutput
        }
        writer.startSession(atSourceTime: .zero)

        install(writer: writer, input: input, adaptor: adaptor)

        appendFrame()
        startTimer()
    }

    func stop() async throws {
        let state = takeStopState()

        guard let writerToFinish = state.writer, let inputToFinish = state.input else {
            throw CaptureError.cancelled
        }

        inputToFinish.markAsFinished()

        await withCheckedContinuation { continuation in
            writerToFinish.finishWriting {
                continuation.resume()
            }
        }

        if writerToFinish.status == .failed {
            throw writerToFinish.error ?? CaptureError.cannotCreateOutput
        }

        guard fileIsUsable(outputURL) else {
            throw CaptureError.cannotCreateOutput
        }
    }

    private func install(writer: AVAssetWriter, input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor) {
        lock.lock()
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        self.frameIndex = 0
        self.isRecording = true
        lock.unlock()
    }

    private func takeStopState() -> (writer: AVAssetWriter?, input: AVAssetWriterInput?) {
        lock.lock()
        isRecording = false
        timer?.cancel()
        timer = nil
        let writerToFinish = writer
        let inputToFinish = input
        writer = nil
        input = nil
        adaptor = nil
        lock.unlock()
        return (writerToFinish, inputToFinish)
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(Int(1000 / frameRate)), leeway: .milliseconds(8))
        timer.setEventHandler { [weak self] in
            self?.appendFrame()
        }

        lock.lock()
        self.timer = timer
        lock.unlock()

        timer.resume()
    }

    private func appendFrame() {
        lock.lock()
        let shouldRecord = isRecording
        let input = self.input
        let adaptor = self.adaptor
        let frameIndex = self.frameIndex
        if input?.isReadyForMoreMediaData == true {
            self.frameIndex += 1
        }
        lock.unlock()

        guard shouldRecord, let input, let adaptor, input.isReadyForMoreMediaData else {
            return
        }
        guard let pixelBuffer = makePixelBuffer() else {
            return
        }

        let time = CMTime(value: frameIndex, timescale: frameRate)
        adaptor.append(pixelBuffer, withPresentationTime: time)
    }

    private func makePixelBuffer() -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(outputSize.width),
            Int(outputSize.height),
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: baseAddress,
                width: Int(outputSize.width),
                height: Int(outputSize.height),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else {
            return nil
        }

        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: outputSize))

        if let image = CGDisplayCreateImage(displayID, rect: captureRectPixels) {
            context.draw(image, in: CGRect(origin: .zero, size: outputSize))
        }

        if showCursor {
            drawCursor(in: context)
        }

        if showClicks {
            drawClickHighlight(in: context)
        }

        return pixelBuffer
    }

    private func drawCursor(in context: CGContext) {
        let mouse = NSEvent.mouseLocation
        guard displayFrame.contains(mouse) else {
            return
        }

        let scaleX = outputSize.width / max(1, captureRectPixels.width)
        let scaleY = outputSize.height / max(1, captureRectPixels.height)
        let localPixels = CGPoint(
            x: (mouse.x - displayFrame.minX) * scaleX - captureRectPixels.minX * scaleX,
            y: (displayFrame.maxY - mouse.y) * scaleY - captureRectPixels.minY * scaleY
        )

        let cursorImage = NSCursor.current.image
        var proposed = CGRect(origin: .zero, size: cursorImage.size)
        guard let cgImage = cursorImage.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            return
        }

        let hotSpot = NSCursor.current.hotSpot
        let size = CGSize(width: cursorImage.size.width * 1.5, height: cursorImage.size.height * 1.5)
        let rect = CGRect(
            x: localPixels.x - hotSpot.x,
            y: outputSize.height - localPixels.y - size.height + hotSpot.y,
            width: size.width,
            height: size.height
        )
        context.draw(cgImage, in: rect)
    }

    private func drawClickHighlight(in context: CGContext) {
        guard CGEventSource.buttonState(.combinedSessionState, button: .left)
            || CGEventSource.buttonState(.combinedSessionState, button: .right) else {
            return
        }

        let mouse = NSEvent.mouseLocation
        guard displayFrame.contains(mouse) else {
            return
        }

        let scaleX = outputSize.width / max(1, captureRectPixels.width)
        let scaleY = outputSize.height / max(1, captureRectPixels.height)
        let local = CGPoint(
            x: (mouse.x - displayFrame.minX) * scaleX - captureRectPixels.minX * scaleX,
            y: (displayFrame.maxY - mouse.y) * scaleY - captureRectPixels.minY * scaleY
        )

        let radius: CGFloat = 22
        let rect = CGRect(x: local.x - radius, y: outputSize.height - local.y - radius, width: radius * 2, height: radius * 2)
        context.setStrokeColor(NSColor.systemYellow.cgColor)
        context.setLineWidth(5)
        context.strokeEllipse(in: rect)
    }

    @MainActor
    private static func screen(for mode: RecordingMode) -> NSScreen? {
        switch mode {
        case .fullScreen:
            return NSScreen.main ?? NSScreen.screens.first
        case .selectedArea(let rect):
            let point = CGPoint(x: rect.midX, y: rect.midY)
            return NSScreen.screens.first { $0.frame.contains(point) }
                ?? NSScreen.main
                ?? NSScreen.screens.first
        }
    }

    @MainActor
    private static func pixelRect(for rect: CGRect, in screen: NSScreen) -> CGRect {
        let intersection = rect.intersection(screen.frame)
        if intersection.isNull || intersection.isEmpty {
            return .zero
        }

        let scale = screen.backingScaleFactor
        return CGRect(
            x: (intersection.minX - screen.frame.minX) * scale,
            y: (screen.frame.maxY - intersection.maxY) * scale,
            width: intersection.width * scale,
            height: intersection.height * scale
        ).integral
    }

    private func fileIsUsable(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return false
        }
        return size > 0
    }
}
