import Foundation
import CoreGraphics

enum ScreenshotGeometryDiagnostics {
    struct DisplayFrame {
        let displayID: UInt32
        let captureFrame: CGRect
        let screenFrame: CGRect
    }

    struct ScreenSegment {
        let displayID: UInt32
        let captureRect: CGRect
        let screenRect: CGRect
    }

    struct EditorTrace {
        let captureID: String?
        let editorID: String
        let selectionScreenRect: CGRect?
    }

    private struct ActiveCapture {
        let id: String
        let startedAt: Date
        let selectionScreenRect: CGRect?
        var resultImageSize: CGSize?
    }

    private static let logQueue = DispatchQueue(label: "com.blademainer.MacScreenCapture.screenshot-geometry-diagnostics")
    private static let maxLogFileSize = 512 * 1024
    private static let signatureLock = NSLock()
    private static var lastSignatures: [String: String] = [:]
    private static let traceLock = NSLock()
    private static var activeCapture: ActiveCapture?

    static func logCaptureSelectedRegion(captureRect: CGRect, displayFrames: [DisplayFrame]) {
        let displays = displayFrames
            .map { "display(id=\($0.displayID),capture=\(rect($0.captureFrame)),screen=\(rect($0.screenFrame)))" }
            .joined(separator: "|")
        let screenSegmentText = screenSegments(for: captureRect, displayFrames: displayFrames)
            .map { "segment(display_id=\($0.displayID),capture=\(rect($0.captureRect)),screen=\(rect($0.screenRect)))" }
            .joined(separator: "|")
        let selectionScreenRect = screenSegments(for: captureRect, displayFrames: displayFrames)
            .map(\.screenRect)
            .reduce(CGRect.null) { partial, segment in
                partial.isNull ? segment : partial.union(segment)
            }
        let captureID = UUID().uuidString

        traceLock.lock()
        activeCapture = ActiveCapture(
            id: captureID,
            startedAt: Date(),
            selectionScreenRect: selectionScreenRect.isNull ? nil : selectionScreenRect,
            resultImageSize: nil
        )
        traceLock.unlock()

        append(event: "capture_selected_region", fields: [
            "capture_id": captureID,
            "capture_rect": rect(captureRect),
            "display_count": "\(displayFrames.count)",
            "displays": displays,
            "selection_screen_rect": selectionScreenRect.isNull ? "none" : rect(selectionScreenRect),
            "selection_screen_segments": screenSegmentText
        ])
    }

    static func screenSegments(for captureRect: CGRect, displayFrames: [DisplayFrame]) -> [ScreenSegment] {
        displayFrames.compactMap { display in
            let intersection = captureRect.intersection(display.captureFrame)
            guard !intersection.isNull, !intersection.isEmpty else { return nil }

            let screenRect = CGRect(
                x: display.screenFrame.minX + (intersection.minX - display.captureFrame.minX),
                y: display.screenFrame.maxY - (intersection.maxY - display.captureFrame.minY),
                width: intersection.width,
                height: intersection.height
            )

            return ScreenSegment(
                displayID: display.displayID,
                captureRect: intersection,
                screenRect: screenRect
            )
        }
    }

    static func logDisplayCropMapping(
        displayID: UInt32,
        displayFrame: CGRect,
        sourceRect: CGRect,
        displayImageSize: CGSize,
        pixelCropRect: CGRect
    ) {
        append(event: "display_crop_mapping", fields: [
            "display_id": "\(displayID)",
            "display_frame": rect(displayFrame),
            "source_rect": rect(sourceRect),
            "display_image_size": size(displayImageSize),
            "pixel_crop_rect": rect(pixelCropRect)
        ])
    }

    static func logCaptureSegment(
        displayID: UInt32,
        displayFrame: CGRect,
        segmentRect: CGRect,
        displayImageSize: CGSize,
        cropImageSize: CGSize
    ) {
        append(event: "capture_segment", fields: [
            "display_id": "\(displayID)",
            "display_frame": rect(displayFrame),
            "segment_rect": rect(segmentRect),
            "display_image_size": size(displayImageSize),
            "crop_image_size": size(cropImageSize)
        ])
    }

    static func logCaptureCompositeSegment(
        captureRect: CGRect,
        sourceRect: CGRect,
        drawRect: CGRect,
        segmentImageSize: CGSize
    ) {
        append(event: "capture_composite_segment", fields: [
            "capture_rect": rect(captureRect),
            "source_rect": rect(sourceRect),
            "draw_rect": rect(drawRect),
            "segment_image_size": size(segmentImageSize)
        ])
    }

    static func logCaptureResult(captureRect: CGRect, resultImageSize: CGSize, segmentCount: Int) {
        traceLock.lock()
        activeCapture?.resultImageSize = resultImageSize
        traceLock.unlock()

        append(event: "capture_result", fields: [
            "capture_rect": rect(captureRect),
            "result_image_size": size(resultImageSize),
            "segment_count": "\(segmentCount)"
        ])
    }

    static func logInlineSegmentLayout(
        selectionCaptureRect: CGRect,
        displayID: UInt32,
        segmentCaptureRect: CGRect,
        segmentScreenRect: CGRect,
        canvasScreenRect: CGRect,
        imageRect: CGRect,
        imageSize: CGSize
    ) {
        appendDeduplicated(event: "inline_segment_layout", fields: [
            "selection_capture_rect": rect(selectionCaptureRect),
            "display_id": "\(displayID)",
            "segment_capture_rect": rect(segmentCaptureRect),
            "segment_screen_rect": rect(segmentScreenRect),
            "canvas_screen_rect": rect(canvasScreenRect),
            "image_rect": rect(imageRect),
            "image_size": size(imageSize)
        ])
    }

    static func makeEditorTrace(for imageSize: CGSize) -> EditorTrace {
        traceLock.lock()
        defer { traceLock.unlock() }

        let matchingCapture = activeCapture.flatMap { capture -> ActiveCapture? in
            guard Date().timeIntervalSince(capture.startedAt) <= 60,
                  let resultSize = capture.resultImageSize,
                  abs(resultSize.width - imageSize.width) <= 1,
                  abs(resultSize.height - imageSize.height) <= 1 else {
                return nil
            }
            return capture
        }

        return EditorTrace(
            captureID: matchingCapture?.id,
            editorID: UUID().uuidString,
            selectionScreenRect: matchingCapture?.selectionScreenRect
        )
    }

    static func logEditorWindowOpened(trace: EditorTrace, imageSize: CGSize, windowFrame: CGRect) {
        append(event: "editor_window_opened", fields: [
            "capture_id": trace.captureID ?? "unmatched",
            "editor_id": trace.editorID,
            "image_size": size(imageSize),
            "selection_screen_rect": trace.selectionScreenRect.map(rect) ?? "none",
            "window_frame": rect(windowFrame)
        ])
    }

    static func logEditorLayout(
        trace: EditorTrace,
        imageSize: CGSize,
        windowSize: CGSize,
        availableSize: CGSize,
        frameSize: CGSize,
        surfacePadding: CGFloat
    ) {
        appendDeduplicated(event: "editor_layout", fields: [
            "capture_id": trace.captureID ?? "unmatched",
            "editor_id": trace.editorID,
            "image_size": size(imageSize),
            "window_size": size(windowSize),
            "available_size": size(availableSize),
            "frame_size": size(frameSize),
            "surface_padding": number(surfacePadding)
        ])
    }

    static func logCanvasLayout(
        trace: EditorTrace?,
        imageSize: CGSize,
        canvasBounds: CGRect,
        imageDisplayRect: CGRect,
        imageScale: CGFloat,
        windowFrame: CGRect?,
        canvasWindowRect: CGRect?,
        canvasScreenRect: CGRect?,
        imageWindowRect: CGRect?,
        imageScreenRect: CGRect?,
        backingScale: CGFloat,
        isFlipped: Bool
    ) {
        var fields: [String: String] = [
            "capture_id": trace?.captureID ?? "unmatched",
            "editor_id": trace?.editorID ?? "unmatched",
            "image_size": size(imageSize),
            "canvas_bounds": rect(canvasBounds),
            "image_display_rect": rect(imageDisplayRect),
            "image_scale": number(imageScale),
            "window_frame": windowFrame.map(rect) ?? "none",
            "canvas_window_rect": canvasWindowRect.map(rect) ?? "none",
            "canvas_screen_rect": canvasScreenRect.map(rect) ?? "none",
            "image_window_rect": imageWindowRect.map(rect) ?? "none",
            "image_screen_rect": imageScreenRect.map(rect) ?? "none",
            "backing_scale": number(backingScale),
            "canvas_is_flipped": isFlipped ? "true" : "false",
            "selection_screen_rect": trace?.selectionScreenRect.map(rect) ?? "none"
        ]

        if let selectionRect = trace?.selectionScreenRect,
           let imageScreenRect,
           selectionRect.width > 0,
           selectionRect.height > 0 {
            fields["image_selection_origin_delta"] = point(CGPoint(
                x: imageScreenRect.minX - selectionRect.minX,
                y: imageScreenRect.minY - selectionRect.minY
            ))
            fields["image_selection_scale"] = size(CGSize(
                width: imageScreenRect.width / selectionRect.width,
                height: imageScreenRect.height / selectionRect.height
            ))
        } else {
            fields["image_selection_origin_delta"] = "none"
            fields["image_selection_scale"] = "none"
        }

        appendDeduplicated(event: "canvas_layout", fields: fields)
    }

    private static func appendDeduplicated(event: String, fields: [String: String]) {
        let signature = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        signatureLock.lock()
        let shouldAppend = lastSignatures[event] != signature
        if shouldAppend {
            lastSignatures[event] = signature
        }
        signatureLock.unlock()

        guard shouldAppend else { return }
        append(event: event, fields: fields)
    }

    private static func append(event: String, fields: [String: String]) {
        var fields = fields
        if fields["capture_id"] == nil {
            traceLock.lock()
            fields["capture_id"] = activeCapture?.id ?? "unmatched"
            traceLock.unlock()
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fieldText = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let line = "\(timestamp) screenshot_geometry event=\(event) \(fieldText)\n"

        logQueue.async {
            do {
                let logURL = persistentLogURL()
                let fileManager = FileManager.default
                try fileManager.createDirectory(
                    at: logURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                if let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
                   let size = attributes[.size] as? NSNumber,
                   size.intValue > maxLogFileSize {
                    try? fileManager.removeItem(at: logURL)
                }

                guard let data = line.data(using: .utf8) else { return }
                if fileManager.fileExists(atPath: logURL.path) {
                    let handle = try FileHandle(forWritingTo: logURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: logURL, options: .atomic)
                }
            } catch {
                print("failed_to_append_screenshot_geometry_record error=\(error.localizedDescription)")
            }
        }
    }

    private static func persistentLogURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacScreenCapture", isDirectory: true)
            .appendingPathComponent("screenshot-geometry.log")
    }

    static func rect(_ rect: CGRect) -> String {
        "rect(x:\(number(rect.origin.x)),y:\(number(rect.origin.y)),w:\(number(rect.size.width)),h:\(number(rect.size.height)))"
    }

    static func size(_ size: CGSize) -> String {
        "size(w:\(number(size.width)),h:\(number(size.height)))"
    }

    static func point(_ point: CGPoint) -> String {
        "point(x:\(number(point.x)),y:\(number(point.y)))"
    }

    private static func number(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}
