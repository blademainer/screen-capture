//
//  CaptureManager.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/25.
//

import Foundation
import SwiftUI
import ScreenCaptureKit
import AVFoundation
import CoreGraphics
import AppKit

/// 捕获管理器 - 负责截图和录制功能的核心逻辑
@available(macOS 12.3, *)
class CaptureManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var captureMode: CaptureMode = .fullScreen
    @Published var selectedDisplay: SCDisplay?
    @Published var selectedWindow: SCWindow?
    @Published var availableDisplays: [SCDisplay] = []
    @Published var availableWindows: [SCWindow] = []
    @Published var lastCapturedImage: NSImage?
    @Published var lastSavedImageURL: URL?
    @Published var recordingURL: URL?
    
    // MARK: - Private Properties
    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var securityScopedURL: URL?
    
    // 线程安全的队列
    private let captureQueue = DispatchQueue(label: "com.macscreencapture.capture", qos: .userInitiated)
    
    // MARK: - Configuration
    private var outputDirectory: URL {
        // 首先尝试使用安全作用域书签
        if let bookmarkData = UserDefaults.standard.data(forKey: "defaultSaveLocationBookmark") {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                if !isStale {
                    // 确保目录存在
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    return url
                }
            } catch {
                print("解析书签失败: \(error)")
            }
        }
        
        // 回退到字符串路径（用于向后兼容）
        let defaultSaveLocation = UserDefaults.standard.string(forKey: "defaultSaveLocation")
        
        let baseURL: URL
        if let customPath = defaultSaveLocation, !customPath.isEmpty {
            baseURL = URL(fileURLWithPath: customPath)
        } else {
            // 默认保存到 Documents/ScreenCaptures
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            baseURL = documentsPath.appendingPathComponent("ScreenCaptures")
        }
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL
    }
    
    /// 获取安全作用域访问的输出目录
    private func getSecureOutputDirectory() -> URL? {
        // 首先尝试使用安全作用域书签
        if let bookmarkData = UserDefaults.standard.data(forKey: "defaultSaveLocationBookmark") {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                if !isStale {
                    // 开始访问安全作用域资源
                    if url.startAccessingSecurityScopedResource() {
                        // 确保目录存在
                        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                        return url
                    } else {
                        print("无法访问安全作用域资源: \(url.path)")
                    }
                }
            } catch {
                print("解析书签失败: \(error)")
            }
        }
        return nil
    }
    
    // MARK: - Initialization
    init() {
        setupNotifications()
    }
    
    deinit {
        // 移除通知观察者
        NotificationCenter.default.removeObserver(self)
        
        // 停止访问安全作用域资源
        securityScopedURL?.stopAccessingSecurityScopedResource()
        
        // 在后台队列中清理资源，避免主线程阻塞
        captureQueue.async { [stream, streamOutput] in
            // 同步停止流
            if let stream = stream {
                // 使用同步方法停止流，避免异步回调
                stream.stopCapture { _ in }
            }
            
            // 完成写入
            streamOutput?.finishWriting()
        }
    }
    
    // MARK: - Public Methods
    
    /// 初始化捕获管理器
    func initialize() {
        Task {
            await updateAvailableContent()
        }
    }
    
    /// 清理资源 - 在应用退出前调用
    @MainActor
    func cleanup() async {
        // 如果正在录制，先停止录制
        if isRecording {
            await stopRecording()
        }
        
        // 停止计时器
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // 在后台队列中清理流资源
        let currentStream = stream
        let currentOutput = streamOutput
        
        await withCheckedContinuation { continuation in
            captureQueue.async {
                // 清理流资源
                if let stream = currentStream {
                    stream.stopCapture { _ in
                        // 完成视频写入
                        currentOutput?.finishWriting()
                        continuation.resume()
                    }
                } else {
                    currentOutput?.finishWriting()
                    continuation.resume()
                }
            }
        }
        
        // 清理资源
        stream = nil
        streamOutput = nil
    }
    
    /// 截图
    func captureScreenshot() async throws -> NSImage {
        guard #available(macOS 12.3, *) else {
            return try await captureLegacyScreenshot()
        }
        
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        let filter: SCContentFilter
        
        switch captureMode {
        case .fullScreen:
            guard let display = selectedDisplay ?? content.displays.first else {
                throw CaptureError.noDisplayAvailable
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
            
        case .window:
            guard let window = selectedWindow else {
                throw CaptureError.noWindowSelected
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            
        case .region:
            // 区域截图需要先选择区域
            return try await captureRegionScreenshot()
        }
        
        let configuration = SCStreamConfiguration()
        
        // 获取显示器尺寸
        let displaySize: CGSize
        if let display = selectedDisplay {
            displaySize = CGSize(width: display.width, height: display.height)
        } else {
            displaySize = CGSize(width: 1920, height: 1080) // 默认尺寸
        }
        
        configuration.width = Int(displaySize.width)
        configuration.height = Int(displaySize.height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        
        // 使用旧版本兼容的截图方法
        return try await captureLegacyScreenshot()
    }
    
    /// 开始录制
    @MainActor
    func startRecording() async throws {
        guard !isRecording else { return }
        guard #available(macOS 12.3, *) else {
            throw CaptureError.unsupportedSystem
        }
        
        // 在后台队列中执行耗时操作
        let (filter, screenSize, outputURL): (SCContentFilter, CGSize, URL) = try await withCheckedThrowingContinuation { continuation in
            captureQueue.async {
                Task {
                    do {
                        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                        
                        var filter: SCContentFilter?
                        
                        await MainActor.run {
                            switch self.captureMode {
                            case .fullScreen:
                                guard let display = self.selectedDisplay ?? content.displays.first else {
                                    continuation.resume(throwing: CaptureError.noDisplayAvailable)
                                    return
                                }
                                filter = SCContentFilter(display: display, excludingWindows: [])
                                
                            case .window:
                                guard let window = self.selectedWindow else {
                                    continuation.resume(throwing: CaptureError.noWindowSelected)
                                    return
                                }
                                filter = SCContentFilter(desktopIndependentWindow: window)
                                
                            case .region:
                                continuation.resume(throwing: CaptureError.regionRecordingNotSupported)
                                return
                            }
                        }
                        
                        guard let finalFilter = filter else {
                            continuation.resume(throwing: CaptureError.noDisplayAvailable)
                            return
                        }
                        
                        // 获取实际屏幕分辨率
                        let screenSize: CGSize = await MainActor.run {
                            if case .fullScreen = self.captureMode, let display = self.selectedDisplay ?? content.displays.first {
                                return CGSize(width: display.width, height: display.height)
                            } else {
                                // 默认使用主屏幕分辨率
                                let mainScreen = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
                                return mainScreen
                            }
                        }
                        
                        // 创建输出文件URL
                        let fileName = "Recording_\(DateFormatter.fileNameFormatter.string(from: Date())).mov"
                        let outputURL = await MainActor.run {
                            self.outputDirectory.appendingPathComponent(fileName)
                        }
                        
                        continuation.resume(returning: (finalFilter, screenSize, outputURL))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
        
        let configuration = SCStreamConfiguration()
        configuration.width = Int(screenSize.width)
        configuration.height = Int(screenSize.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30) // 30 FPS
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange // 使用 YUV 格式，更适合 H.264
        configuration.showsCursor = true
        configuration.queueDepth = 5
        configuration.colorSpaceName = CGColorSpace.sRGB // 使用标准 sRGB 色彩空间
        
        if #available(macOS 13.0, *) {
            configuration.capturesAudio = true
        }
        
        print("录制配置: \(Int(screenSize.width))x\(Int(screenSize.height)) @ 30fps")
        
        recordingURL = outputURL
        print("录制文件路径: \(recordingURL!.path)")
        
        // 创建流输出
        streamOutput = CaptureStreamOutput(outputURL: recordingURL!)
        
        // 创建并启动流
        stream = SCStream(filter: filter, configuration: configuration, delegate: streamOutput)
        
        // 添加视频流输出
        try stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: captureQueue)
        
        // 添加音频流输出（如果支持）
        if #available(macOS 13.0, *) {
            try stream?.addStreamOutput(streamOutput!, type: .audio, sampleHandlerQueue: captureQueue)
        }
        
        print("开始启动录制流...")
        try await stream?.startCapture()
        print("录制流启动成功")
        
        // 更新状态
        isRecording = true
        isPaused = false
        recordingStartTime = Date()
        startRecordingTimer()
        
        // 发送通知
        NotificationCenter.default.post(name: .recordingDidStart, object: nil)
    }
    
    /// 停止录制
    @MainActor
    func stopRecording() async {
        guard isRecording else { return }
        
        print("正在停止录制...")
        
        // 停止计时器
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // 在后台队列中停止流
        let currentStream = stream
        let currentOutput = streamOutput
        let currentURL = recordingURL
        
        await withCheckedContinuation { continuation in
            captureQueue.async {
                // 停止捕获流
                if let stream = currentStream {
                    stream.stopCapture { _ in
                        // 完成视频写入
                        currentOutput?.finishWriting()
                        continuation.resume()
                    }
                } else {
                    currentOutput?.finishWriting()
                    continuation.resume()
                }
            }
        }
        
        // 更新状态
        isRecording = false
        isPaused = false
        recordingDuration = 0
        recordingStartTime = nil
        
        // 清理资源
        stream = nil
        streamOutput = nil
        
        print("录制已停止")
        
        // 发送通知
        NotificationCenter.default.post(name: .recordingDidStop, object: currentURL)
    }
    
    /// 暂停/恢复录制
    @MainActor
    func togglePauseRecording() {
        guard isRecording else { return }
        
        if isPaused {
            // 恢复录制
            recordingStartTime = Date().addingTimeInterval(-recordingDuration)
            startRecordingTimer()
            isPaused = false
        } else {
            // 暂停录制
            recordingTimer?.invalidate()
            recordingTimer = nil
            isPaused = true
        }
    }
    
    /// 更新可用内容
    @MainActor
    func updateAvailableContent() async {
        guard #available(macOS 12.3, *) else { return }
        
        do {
            // 在后台队列中获取内容
            let (displays, windows) = try await withCheckedThrowingContinuation { continuation in
                captureQueue.async {
                    Task {
                        do {
                            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                            
                            let displays = content.displays
                            let windows = content.windows.filter { window in
                                window.title?.isEmpty == false && window.frame.width > 100 && window.frame.height > 100
                            }
                            
                            continuation.resume(returning: (displays, windows))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
            
            // 在主线程上更新 UI
            availableDisplays = displays
            availableWindows = windows
            
            // 设置默认选择
            if selectedDisplay == nil {
                selectedDisplay = availableDisplays.first
            }
            
        } catch {
            print("Failed to get shareable content: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    /// 设置通知监听
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDisplayConfigurationChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    /// 处理显示器配置变化
    @objc private func handleDisplayConfigurationChange() {
        Task { @MainActor in
            await updateAvailableContent()
        }
    }
    
    /// 开始录制计时器
    @MainActor
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    /// 保存截图
    private func saveScreenshot(_ image: NSImage) async throws {
        // 获取用户设置的图片格式
        let screenshotFormat = UserDefaults.standard.string(forKey: "screenshotFormat") ?? "PNG"
        let fileExtension = screenshotFormat.lowercased()
        
        let fileName = "Screenshot_\(DateFormatter.fileNameFormatter.string(from: Date())).\(fileExtension)"
        
        // 使用安全作用域资源访问
        var securityScopedURL: URL?
        var needsSecurityScope = false
        
        // 检查是否有安全作用域书签
        if let bookmarkData = UserDefaults.standard.data(forKey: "defaultSaveLocationBookmark") {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                if !isStale && url.startAccessingSecurityScopedResource() {
                    securityScopedURL = url
                    needsSecurityScope = true
                }
            } catch {
                print("解析书签失败: \(error)")
            }
        }
        
        let baseDirectory = securityScopedURL ?? outputDirectory
        let fileURL = baseDirectory.appendingPathComponent(fileName)
        
        defer {
            // 确保在方法结束时停止访问安全作用域资源
            if needsSecurityScope, let scopedURL = securityScopedURL {
                scopedURL.stopAccessingSecurityScopedResource()
            }
        }
        
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            throw CaptureError.failedToSaveImage
        }
        
        // 根据格式选择相应的数据表示
        let imageData: Data?
        switch screenshotFormat.uppercased() {
        case "JPEG":
            imageData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        case "TIFF":
            imageData = bitmapRep.representation(using: .tiff, properties: [:])
        default: // PNG
            imageData = bitmapRep.representation(using: .png, properties: [:])
        }
        
        guard let finalData = imageData else {
            throw CaptureError.failedToSaveImage
        }
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        
        try finalData.write(to: fileURL)
        
        // 更新最后保存的文件URL
        await MainActor.run {
            lastSavedImageURL = fileURL
        }
        
        // 发送通知
        NotificationCenter.default.post(name: .screenshotDidSave, object: fileURL)
    }
    
    /// 区域截图 - 使用系统截图工具
    private func captureRegionScreenshot() async throws -> NSImage {
        // 使用系统的截图工具进行区域选择
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        
        // 创建临时文件
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("temp_region_capture_\(UUID().uuidString).png")
        
        // 设置参数：-i 表示交互式选择区域，-r 表示只捕获选定区域
        process.arguments = ["-i", "-r", tempURL.path]
        
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                Task { @MainActor in
                    if process.terminationStatus == 0 {
                        // 截图成功，读取图片
                        if let image = NSImage(contentsOf: tempURL) {
                            // 保存到正式目录
                            do {
                                try await self.saveScreenshot(image)
                                self.lastCapturedImage = image
                                
                                // 清理临时文件
                                try? FileManager.default.removeItem(at: tempURL)
                                
                                continuation.resume(returning: image)
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        } else {
                            continuation.resume(throwing: CaptureError.failedToCapture)
                        }
                    } else {
                        // 用户取消了截图
                        try? FileManager.default.removeItem(at: tempURL)
                        continuation.resume(throwing: CaptureError.regionSelectionCancelled)
                    }
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: CaptureError.failedToCapture)
            }
        }
    }
    
    /// 捕获指定区域
    private func captureRegion(_ rect: NSRect) async throws -> NSImage {
        guard #available(macOS 12.3, *) else {
            return try await captureLegacyRegion(rect)
        }
        
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        guard let display = content.displays.first(where: { display in
            display.frame.intersects(rect)
        }) else {
            throw CaptureError.noDisplayAvailable
        }
        
        _ = SCContentFilter(display: display, excludingWindows: [])
        
        let configuration = SCStreamConfiguration()
        configuration.width = Int(rect.width)
        configuration.height = Int(rect.height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        
        // 设置源区域
        configuration.sourceRect = rect
        
        // 使用旧版本兼容的截图方法
        return try await captureLegacyRegion(rect)
    }
    
    /// 旧系统区域截图方法
    private func captureLegacyRegion(_ rect: NSRect) async throws -> NSImage {
        let displayID = CGMainDisplayID()
        
        guard let cgImage = CGDisplayCreateImage(displayID) else {
            throw CaptureError.failedToCapture
        }
        
        // 裁剪图像到指定区域
        let scale = CGFloat(cgImage.width) / NSScreen.main!.frame.width
        let scaledRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        
        guard let croppedImage = cgImage.cropping(to: scaledRect) else {
            throw CaptureError.failedToCapture
        }
        
        let nsImage = NSImage(cgImage: croppedImage, size: rect.size)
        
        try await saveScreenshot(nsImage)
        lastCapturedImage = nsImage
        
        return nsImage
    }
    
    /// 旧系统截图方法
    private func captureLegacyScreenshot() async throws -> NSImage {
        let displayID = CGMainDisplayID()
        
        guard let cgImage = CGDisplayCreateImage(displayID) else {
            throw CaptureError.failedToCapture
        }
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        
        try await saveScreenshot(nsImage)
        lastCapturedImage = nsImage
        
        return nsImage
    }
}

// MARK: - Capture Mode

enum CaptureMode: String, CaseIterable {
    case fullScreen = "全屏"
    case window = "窗口"
    case region = "区域"
    
    var systemImage: String {
        switch self {
        case .fullScreen: return "display"
        case .window: return "macwindow"
        case .region: return "crop"
        }
    }
}

// MARK: - Capture Errors

enum CaptureError: LocalizedError {
    case noDisplayAvailable
    case noWindowSelected
    case regionRecordingNotSupported
    case regionSelectionCancelled
    case unsupportedSystem
    case failedToCapture
    case failedToSaveImage
    
    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "没有可用的显示器"
        case .noWindowSelected:
            return "没有选择窗口"
        case .regionRecordingNotSupported:
            return "区域录制暂不支持"
        case .regionSelectionCancelled:
            return "区域选择已取消"
        case .unsupportedSystem:
            return "系统版本不支持"
        case .failedToCapture:
            return "捕获失败"
        case .failedToSaveImage:
            return "保存图片失败"
        }
    }
}

// MARK: - Stream Output

@available(macOS 12.3, *)
class CaptureStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    private let outputURL: URL
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var isWritingStarted = false
    private var frameCount = 0
    private var audioFrameCount = 0
    private var micFrameCount = 0
    
    init(outputURL: URL) {
        self.outputURL = outputURL
        super.init()
    }
    
    func setupAssetWriter(with sampleBuffer: CMSampleBuffer) {
        do {
            // 删除已存在的文件
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            
            // 使用 QuickTime 格式以确保最佳兼容性
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            
            // 从样本缓冲区获取实际的视频尺寸
            guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
                print("无法获取格式描述")
                return
            }
            
            let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
            let width = Int(dimensions.width)
            let height = Int(dimensions.height)
            
            print("录制分辨率: \(width)x\(height)")
            
            // 确保宽度和高度是偶数（H.264 要求）
            let adjustedWidth = (width % 2 == 0) ? width : width - 1
            let adjustedHeight = (height % 2 == 0) ? height : height - 1
            
            print("调整后录制分辨率: \(adjustedWidth)x\(adjustedHeight)")
            
            // 视频输入设置 - 使用 QuickTime 兼容的 H.264 设置
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: adjustedWidth,
                AVVideoHeightKey: adjustedHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
                    AVVideoAverageBitRateKey: 5000000,
                    AVVideoMaxKeyFrameIntervalKey: 30,
                    AVVideoAllowFrameReorderingKey: false,
                    AVVideoExpectedSourceFrameRateKey: 30,
                    AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCAVLC
                ]
            ]
            
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true
            
            // 设置变换矩阵以确保正确的方向
            videoInput?.transform = CGAffineTransform.identity
            
            // 创建像素缓冲区适配器
            let pixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: adjustedWidth,
                kCVPixelBufferHeightKey as String: adjustedHeight,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            
            if let videoInput = videoInput {
                pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: videoInput,
                    sourcePixelBufferAttributes: pixelBufferAttributes
                )
                
                if assetWriter?.canAdd(videoInput) == true {
                    assetWriter?.add(videoInput)
                }
            }
            
            // 音频输入设置
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000
            ]
            
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput?.expectsMediaDataInRealTime = true
            
            if let audioInput = audioInput, assetWriter?.canAdd(audioInput) == true {
                assetWriter?.add(audioInput)
            }
            
        } catch {
            print("设置资产写入器失败: \(error)")
        }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // 如果还没有设置资产写入器，先设置
        if assetWriter == nil && type == .screen {
            print("首次收到视频帧，设置资产写入器...")
            setupAssetWriter(with: sampleBuffer)
        }
        
        guard let assetWriter = assetWriter else { 
            print("资产写入器未初始化")
            return 
        }
        
        // 开始写入会话
        if !isWritingStarted && assetWriter.status == .unknown {
            guard assetWriter.startWriting() else {
                print("开始写入失败: \(assetWriter.error?.localizedDescription ?? "未知错误")")
                return
            }
            assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            isWritingStarted = true
            print("录制会话已开始，时间戳: \(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))")
        }
        
        // 检查写入状态
        guard assetWriter.status == .writing else {
            print("资产写入器状态异常: \(assetWriter.status.rawValue)")
            if let error = assetWriter.error {
                print("写入器错误: \(error.localizedDescription)")
            }
            return
        }
        
        switch type {
        case .screen:
            if let videoInput = videoInput, videoInput.isReadyForMoreMediaData {
                // 获取像素缓冲区
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                    print("无法获取像素缓冲区")
                    return
                }
                
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                
                // 使用像素缓冲区适配器写入
                if let adaptor = pixelBufferAdaptor, adaptor.assetWriterInput.isReadyForMoreMediaData {
                    if adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                        frameCount += 1
                        if frameCount % 100 == 0 {
                            print("已写入 \(frameCount) 个视频帧")
                        }
                    } else {
                        print("像素缓冲区适配器写入失败")
                    }
                } else {
                    // 回退到直接写入样本缓冲区
                    if videoInput.append(sampleBuffer) {
                        frameCount += 1
                        if frameCount % 100 == 0 {
                            print("已写入 \(frameCount) 个视频帧 (直接模式)")
                        }
                    } else {
                        print("视频帧写入失败")
                    }
                }
            } else {
                print("视频输入未准备好或不存在")
            }
        case .audio:
            if let audioInput = audioInput, audioInput.isReadyForMoreMediaData {
                if audioInput.append(sampleBuffer) {
                    audioFrameCount += 1
                    if audioFrameCount % 100 == 0 {
                        print("已写入 \(audioFrameCount) 个音频帧")
                    }
                } else {
                    print("音频帧写入失败")
                }
            }
        case .microphone:
            if let audioInput = audioInput, audioInput.isReadyForMoreMediaData {
                if audioInput.append(sampleBuffer) {
                    micFrameCount += 1
                    if micFrameCount % 100 == 0 {
                        print("已写入 \(micFrameCount) 个麦克风音频帧")
                    }
                } else {
                    print("麦克风音频写入失败")
                }
            }
        @unknown default:
            print("未知的流类型: \(type)")
            break
        }
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("录制流停止，错误: \(error)")
        DispatchQueue.main.async {
            self.finishWriting()
        }
    }
    
    func finishWriting() {
        guard let assetWriter = assetWriter else {
            print("资产写入器为空，无法完成写入")
            return
        }
        
        print("开始完成录制写入...")
        
        // 标记输入完成
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        
        // 完成写入
        assetWriter.finishWriting { [weak self] in
            DispatchQueue.main.async {
                if let error = assetWriter.error {
                    print("录制完成时出错: \(error.localizedDescription)")
                } else {
                    print("录制成功完成，文件保存至: \(self?.outputURL.path ?? "未知路径")")
                    
                    // 验证文件是否存在且有效
                    if let url = self?.outputURL, FileManager.default.fileExists(atPath: url.path) {
                        do {
                            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                            let fileSize = attributes[.size] as? Int64 ?? 0
                            print("录制文件大小: \(fileSize) 字节")
                            
                            if fileSize > 0 {
                                print("录制文件有效")
                            } else {
                                print("警告: 录制文件大小为0")
                            }
                        } catch {
                            print("无法获取文件属性: \(error)")
                        }
                    } else {
                        print("错误: 录制文件不存在")
                    }
                }
            }
        }
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}

extension Notification.Name {
    static let recordingDidStart = Notification.Name("recordingDidStart")
    static let recordingDidStop = Notification.Name("recordingDidStop")
    static let screenshotDidSave = Notification.Name("screenshotDidSave")
}