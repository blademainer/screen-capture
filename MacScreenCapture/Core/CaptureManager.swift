//
//  CaptureManager.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/25.
//

import Foundation
import SwiftUI
@preconcurrency import ScreenCaptureKit
import AVFoundation
import CoreGraphics
import AppKit

/// 捕获管理器 - 负责截图和录制功能的核心逻辑
@available(macOS 12.3, *)
class CaptureManager: ObservableObject {
    
    // MARK: - Singleton
    static let shared = CaptureManager()
    
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
        setupDefaultSettings()
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
    
    // MARK: - Hotkey Action Methods
    
    /// 全屏截图 - 快捷键调用
    @MainActor
    func captureFullScreen() async {
        do {
            let originalMode = captureMode
            captureMode = .fullScreen
            _ = try await captureScreenshot()
            captureMode = originalMode
        } catch {
            print("全屏截图失败: \(error)")
        }
    }
    
    /// 区域截图 - 快捷键调用
    @MainActor
    func captureRegion() async {
        do {
            let originalMode = captureMode
            captureMode = .region
            _ = try await captureScreenshot()
            captureMode = originalMode
        } catch {
            print("区域截图失败: \(error)")
        }
    }
    
    /// 窗口截图 - 快捷键调用
    @MainActor
    func captureWindow() async {
        do {
            let originalMode = captureMode
            captureMode = .window
            _ = try await captureScreenshot()
            captureMode = originalMode
        } catch {
            print("窗口截图失败: \(error)")
        }
    }
    
    /// 滚动截图 - 快捷键调用
    @MainActor
    func captureScrollingWindow() async {
        // 滚动截图功能暂未实现，显示提示
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "功能开发中"
            alert.informativeText = "滚动截图功能正在开发中，敬请期待。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
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
        // 通知WindowManager开始截图
        await MainActor.run {
            WindowManager.shared.updateCaptureState(.screenshotting)
        }
        
        defer {
            // 截图完成后恢复状态
            Task { @MainActor in
                WindowManager.shared.updateCaptureState(.idle)
            }
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
        
        // 使用 ScreenCaptureKit 进行截图
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        
        try await saveScreenshot(nsImage)
        lastCapturedImage = nsImage
        
        return nsImage
    }
    
    /// 开始录制
    @MainActor
    func startRecording() async throws {
        guard !isRecording else { return }

        logMicrophone("========== 开始录制流程 ==========")
        
        // 检查麦克风权限（如果用户启用了麦克风录制）
        let includeMicrophonePreference = UserDefaults.standard.bool(forKey: "includeMicrophone")
        logMicrophone("用户设置 - includeMicrophone: \(includeMicrophonePreference)")
        
        if includeMicrophonePreference {
            let permissionManager = PermissionManager()
            
            // 检查麦克风设备是否可用
            let deviceAvailable = permissionManager.checkMicrophoneDeviceAvailable()
            logMicrophone("麦克风设备可用性: \(deviceAvailable)", level: deviceAvailable ? "SUCCESS" : "ERROR")
            
            if !deviceAvailable {
                print("⚠️ 警告：未检测到可用的麦克风设备")
                // 显示警告但继续录制
                let shouldContinue = await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "未检测到麦克风"
                    alert.informativeText = "系统未检测到可用的麦克风设备，将仅录制屏幕和系统音频。"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "继续")
                    alert.addButton(withTitle: "取消")
                    
                    return alert.runModal() != .alertSecondButtonReturn
                }
                
                if !shouldContinue {
                    throw CaptureError.noMicrophoneAvailable
                }
            }
            
            // 异步请求麦克风权限并等待结果
            let hasPermission = await permissionManager.requestMicrophonePermissionAsync()
            logMicrophone("麦克风权限状态: \(hasPermission)", level: hasPermission ? "SUCCESS" : "ERROR")
            
            if !hasPermission {
                print("⚠️ 警告：麦克风权限未授予")
                // 显示警告但继续录制
                let shouldContinue = await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "麦克风权限未授予"
                    alert.informativeText = "无法录制麦克风音频，将仅录制屏幕和系统音频。是否继续？"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "继续")
                    alert.addButton(withTitle: "取消")
                    
                    return alert.runModal() != .alertSecondButtonReturn
                }
                
                if !shouldContinue {
                    throw CaptureError.microphonePermissionDenied
                }
                // 禁用麦克风录制
                UserDefaults.standard.set(false, forKey: "includeMicrophone")
            } else {
                print("✓ 麦克风权限已授予")
            }
        }
        
        // 通知WindowManager开始录制
        WindowManager.shared.updateCaptureState(.recording(startTime: Date()))
        
        // 在后台队列中执行耗时操作
        let (filter, screenSize, outputURL): (SCContentFilter, CGSize, URL) = try await withCheckedThrowingContinuation { continuation in
            captureQueue.async {
                Task {
                    do {
                        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                        
                        // 使用局部变量来避免在 MainActor.run 中调用 continuation.resume
                        var captureError: CaptureError?
                        var filter: SCContentFilter?
                        
                        await MainActor.run {
                            switch self.captureMode {
                            case .fullScreen:
                                guard let display = self.selectedDisplay ?? content.displays.first else {
                                    captureError = CaptureError.noDisplayAvailable
                                    return
                                }
                                filter = SCContentFilter(display: display, excludingWindows: [])
                                
                            case .window:
                                guard let window = self.selectedWindow else {
                                    captureError = CaptureError.noWindowSelected
                                    return
                                }
                                filter = SCContentFilter(desktopIndependentWindow: window)
                                
                            case .region:
                                captureError = CaptureError.regionRecordingNotSupported
                                return
                            }
                        }
                        
                        // 检查是否有错误
                        if let error = captureError {
                            continuation.resume(throwing: error)
                            return
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
        
        // 根据用户设置决定是否录制音频
        let includeSystemAudio = UserDefaults.standard.bool(forKey: "includeSystemAudio")
        let includeMicrophone = UserDefaults.standard.bool(forKey: "includeMicrophone")
        
        configuration.capturesAudio = includeSystemAudio
        configuration.captureMicrophone = includeMicrophone
        
        logMicrophone("SCStreamConfiguration 配置:")
        logMicrophone("  - capturesAudio: \(includeSystemAudio)")
        logMicrophone("  - captureMicrophone: \(includeMicrophone)", level: includeMicrophone ? "SUCCESS" : "WARN")
        
        print("音频录制设置 - 系统音频: \(includeSystemAudio), 麦克风: \(includeMicrophone)")
        
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
        if includeSystemAudio {
            try stream?.addStreamOutput(streamOutput!, type: .audio, sampleHandlerQueue: captureQueue)
            logMicrophone("✓ 已添加系统音频流输出", level: "SUCCESS")
            print("已添加系统音频流输出")
        }
        
        if includeMicrophone {
            do {
                try stream?.addStreamOutput(streamOutput!, type: .microphone, sampleHandlerQueue: captureQueue)
                logMicrophone("✓ 已成功添加麦克风音频流输出到 SCStream", level: "SUCCESS")
                print("已添加麦克风音频流输出")
            } catch {
                logMicrophone("✗ 添加麦克风音频流输出失败: \(error.localizedDescription)", level: "ERROR")
                throw error
            }
        } else {
            logMicrophone("⚠️ 麦克风录制未启用，跳过添加麦克风流", level: "WARN")
        }
        
        print("开始启动录制流...")
        try await stream?.startCapture()
        print("录制流启动成功")
        
        logMicrophone("========== SCStream 启动成功 ==========", level: "SUCCESS")
        logMicrophone("等待接收音频帧...")
        logMicrophone("如果 5 秒后没有看到麦克风音频帧，说明麦克风流未正常工作")
        
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
        
        // 通知WindowManager录制停止
        WindowManager.shared.updateCaptureState(.idle)
        
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
            WindowManager.shared.updateCaptureState(.recording(startTime: recordingStartTime!))
        } else {
            // 暂停录制
            recordingTimer?.invalidate()
            recordingTimer = nil
            isPaused = true
            WindowManager.shared.updateCaptureState(.paused(duration: recordingDuration))
        }
    }
    
    /// 恢复录制 - 快捷键调用
    @MainActor
    func resumeRecording() async {
        guard isRecording && isPaused else { return }
        
        // 恢复录制
        recordingStartTime = Date().addingTimeInterval(-recordingDuration)
        startRecordingTimer()
        isPaused = false
        WindowManager.shared.updateCaptureState(.recording(startTime: recordingStartTime!))
        
        print("录制已恢复")
    }
    
    /// 更新可用内容
    @MainActor
    func updateAvailableContent() async {

        
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
    
    /// 设置默认录制设置
    private func setupDefaultSettings() {
        // 如果是首次启动，设置默认值
        if !UserDefaults.standard.bool(forKey: "hasSetupDefaultRecordingSettings") {
            UserDefaults.standard.set(true, forKey: "includeSystemAudio")
            UserDefaults.standard.set(true, forKey: "includeMicrophone")
            UserDefaults.standard.set(true, forKey: "showCursor")
            UserDefaults.standard.set(60.0, forKey: "recordingFrameRate")
            UserDefaults.standard.set("高", forKey: "recordingQuality")
            UserDefaults.standard.set(true, forKey: "hasSetupDefaultRecordingSettings")
            
            print("已设置默认录制设置 - 麦克风录制已启用")
        }
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
        // 通知WindowManager开始截图
        await MainActor.run {
            WindowManager.shared.updateCaptureState(.screenshotting)
        }
        
        defer {
            // 截图完成后恢复状态
            Task { @MainActor in
                WindowManager.shared.updateCaptureState(.idle)
            }
        }
        
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
                                
                                // 显示编辑窗口
                                WindowManager.shared.showEditingWindow(for: image)
                                
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
        // 使用 ScreenCaptureKit 替代已弃用的 CGDisplayCreateImage
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw CaptureError.noDisplayAvailable
        }
        
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(display.width)
        configuration.height = Int(display.height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        
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
        // 使用 ScreenCaptureKit 替代已弃用的 CGDisplayCreateImage
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw CaptureError.noDisplayAvailable
        }
        
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(display.width)
        configuration.height = Int(display.height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        
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
    case noMicrophoneAvailable
    case microphonePermissionDenied
    
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
        case .noMicrophoneAvailable:
            return "没有可用的麦克风设备"
        case .microphonePermissionDenied:
            return "麦克风权限被拒绝"
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
    private var microphoneInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var isWritingStarted = false
    private var frameCount = 0
    private var audioFrameCount = 0
    private var micFrameCount = 0
    private var audioFailCount = 0
    private var micFailCount = 0
    
    init(outputURL: URL) {
        self.outputURL = outputURL
        super.init()
    }
    
    func setupAssetWriter(with sampleBuffer: CMSampleBuffer) {
        do {
            logMicrophone("========== 设置 AVAssetWriter ==========")
            logMicrophone("输出文件路径: \(outputURL.path)")
            logMicrophone("输出文件 URL: \(outputURL.absoluteString)")
            
            // 确保父目录存在
            let parentDirectory = outputURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDirectory.path) {
                logMicrophone("父目录不存在，正在创建: \(parentDirectory.path)")
                try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
            } else {
                logMicrophone("父目录已存在: \(parentDirectory.path)")
            }
            
            // 删除已存在的文件
            if FileManager.default.fileExists(atPath: outputURL.path) {
                logMicrophone("删除已存在的文件: \(outputURL.path)")
                try FileManager.default.removeItem(at: outputURL)
            }
            
            // 使用 QuickTime 格式以确保最佳兼容性
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            logMicrophone("✓ AVAssetWriter 创建成功", level: "SUCCESS")
            
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
            
            // 检查是否需要音频输入
            let includeSystemAudio = UserDefaults.standard.bool(forKey: "includeSystemAudio")
            let includeMicrophone = UserDefaults.standard.bool(forKey: "includeMicrophone")
            
            logMicrophone("AVAssetWriter 音频配置:")
            logMicrophone("  - includeSystemAudio: \(includeSystemAudio)")
            logMicrophone("  - includeMicrophone: \(includeMicrophone)")
            
            print("🎵 音频配置 - 系统音频: \(includeSystemAudio), 麦克风: \(includeMicrophone)")
            
            // 新策略：创建两个独立的音频输入，分别用于系统音频和麦克风
            // 使用标准的 AAC 编码以确保 QuickTime 兼容性
            if includeSystemAudio || includeMicrophone {
                // 标准 AAC 音频设置 - QuickTime 兼容
                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128000
                ]
                
                if includeSystemAudio {
                    // 系统音频输入
                    audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                    audioInput?.expectsMediaDataInRealTime = true
                    
                    if let audioInput = audioInput, assetWriter?.canAdd(audioInput) == true {
                        assetWriter?.add(audioInput)
                        logMicrophone("✓ 系统音频输入已添加 (AAC 48kHz 立体声)", level: "SUCCESS")
                        print("✓ 系统音频输入已添加到资产写入器")
                    } else {
                        logMicrophone("✗ 无法添加系统音频输入", level: "ERROR")
                    }
                }
                
                if includeMicrophone {
                    // 麦克风音频输入 - 使用相同的设置以确保兼容性
                    microphoneInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                    microphoneInput?.expectsMediaDataInRealTime = true
                    
                    if let microphoneInput = microphoneInput, assetWriter?.canAdd(microphoneInput) == true {
                        assetWriter?.add(microphoneInput)
                        logMicrophone("✓ 麦克风音频输入已添加 (AAC 48kHz 立体声)", level: "SUCCESS")
                        print("✓ 麦克风音频输入已添加到资产写入器")
                    } else {
                        logMicrophone("✗ 无法添加麦克风音频输入", level: "ERROR")
                    }
                }
                
                logMicrophone("音频配置完成:")
                logMicrophone("  - 系统音频: \(includeSystemAudio ? "启用" : "禁用")")
                logMicrophone("  - 麦克风: \(includeMicrophone ? "启用" : "禁用")")
                logMicrophone("  - 编码格式: AAC 48kHz 立体声")
            } else {
                print("⚠️ 未启用任何音频录制")
            }
            
        } catch {
            print("设置资产写入器失败: \(error)")
        }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // 如果还没有设置资产写入器，先设置（只在收到视频帧时设置）
        if assetWriter == nil && type == .screen {
            print("首次收到视频帧，设置资产写入器...")
            setupAssetWriter(with: sampleBuffer)
        }
        
        // 如果资产写入器还未初始化，且当前不是视频帧，则等待视频帧到来
        guard let assetWriter = assetWriter else {
            if type != .screen {
                // 音频帧在视频帧之前到达，等待视频帧初始化资产写入器
                return
            }
            print("资产写入器未初始化")
            return
        }
        
        // 开始写入会话（使用第一个到达的帧的时间戳）
        if !isWritingStarted && assetWriter.status == .unknown {
            guard assetWriter.startWriting() else {
                print("开始写入失败: \(assetWriter.error?.localizedDescription ?? "未知错误")")
                logMicrophone("✗ AVAssetWriter.startWriting() 失败: \(assetWriter.error?.localizedDescription ?? "未知错误")", level: "ERROR")
                return
            }
            let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter.startSession(atSourceTime: startTime)
            isWritingStarted = true
            print("录制会话已开始，时间戳: \(startTime), 帧类型: \(type)")
            logMicrophone("✓ AVAssetWriter 会话已启动，起始时间: \(startTime)", level: "SUCCESS")
        }
        
        // 检查写入状态
        guard assetWriter.status == .writing else {
            print("资产写入器状态异常: \(assetWriter.status.rawValue)")
            if let error = assetWriter.error {
                print("写入器错误: \(error.localizedDescription)")
                logMicrophone("✗ AVAssetWriter 状态错误: \(error.localizedDescription)", level: "ERROR")
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
            // 系统音频 - 写入到 audioInput
            if audioFrameCount == 0 && audioFailCount == 0 {
                logMicrophone("📥 收到首个系统音频帧", level: "INFO")
                logMicrophone("  - AVAssetWriter.status: \(assetWriter.status.rawValue)")
                logMicrophone("  - isWritingStarted: \(isWritingStarted)")
                if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                    if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                        logMicrophone("  - 音频格式: \(asbd.pointee.mSampleRate)Hz, \(asbd.pointee.mChannelsPerFrame)声道")
                    }
                }
            }
            
            if let audioInput = audioInput {
                if audioInput.isReadyForMoreMediaData {
                    if audioInput.append(sampleBuffer) {
                        audioFrameCount += 1
                        if audioFrameCount == 1 {
                            logMicrophone("✓ 首个系统音频帧写入成功", level: "SUCCESS")
                            print("✓ 首个系统音频帧写入成功")
                        }
                        if audioFrameCount % 100 == 0 {
                            logMicrophone("🎵 已写入 \(audioFrameCount) 个系统音频帧")
                            print("🎵 已写入 \(audioFrameCount) 个系统音频帧")
                        }
                    } else {
                        audioFailCount += 1
                        if audioFailCount <= 5 {
                            logMicrophone("✗ 系统音频帧写入失败 (失败计数: \(audioFailCount))", level: "ERROR")
                            logMicrophone("  - AVAssetWriter.status: \(assetWriter.status.rawValue)", level: "ERROR")
                            if let error = assetWriter.error {
                                logMicrophone("  - 错误: \(error.localizedDescription)", level: "ERROR")
                                logMicrophone("  - 错误代码: \(error._code)", level: "ERROR")
                            }
                        }
                    }
                } else {
                    if audioFrameCount == 0 && audioFailCount == 0 {
                        logMicrophone("⚠️ 系统音频输入未准备好接收数据", level: "WARN")
                    }
                }
            } else {
                if audioFrameCount == 0 && audioFailCount == 0 {
                    logMicrophone("✗ 系统音频输入不存在", level: "ERROR")
                }
            }
            
        case .microphone:
            // 麦克风音频 - 写入到 microphoneInput
            if micFrameCount == 0 && micFailCount == 0 {
                logMicrophone("📥 收到首个麦克风音频帧", level: "INFO")
                logMicrophone("  - AVAssetWriter.status: \(assetWriter.status.rawValue)")
                logMicrophone("  - isWritingStarted: \(isWritingStarted)")
                if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                    if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                        logMicrophone("  - 音频格式: \(asbd.pointee.mSampleRate)Hz, \(asbd.pointee.mChannelsPerFrame)声道")
                    }
                }
            }
            
            if let microphoneInput = microphoneInput {
                if microphoneInput.isReadyForMoreMediaData {
                    if microphoneInput.append(sampleBuffer) {
                        micFrameCount += 1
                        if micFrameCount == 1 {
                            logMicrophone("✓ 首个麦克风音频帧写入成功！", level: "SUCCESS")
                            print("✓ 首个麦克风音频帧写入成功")
                        }
                        if micFrameCount % 100 == 0 {
                            logMicrophone("🎤 已写入 \(micFrameCount) 个麦克风音频帧")
                            print("🎤 已写入 \(micFrameCount) 个麦克风音频帧")
                        }
                    } else {
                        micFailCount += 1
                        if micFailCount <= 5 {
                            logMicrophone("✗ 麦克风音频帧写入失败 (失败计数: \(micFailCount))", level: "ERROR")
                            logMicrophone("  - AVAssetWriter.status: \(assetWriter.status.rawValue)", level: "ERROR")
                            if let error = assetWriter.error {
                                logMicrophone("  - 错误: \(error.localizedDescription)", level: "ERROR")
                                logMicrophone("  - 错误代码: \(error._code)", level: "ERROR")
                            }
                        }
                    }
                } else {
                    if micFrameCount == 0 && micFailCount == 0 {
                        logMicrophone("⚠️ 麦克风输入未准备好接收数据", level: "WARN")
                    }
                }
            } else {
                if micFrameCount == 0 && micFailCount == 0 {
                    logMicrophone("✗ 麦克风输入不存在", level: "ERROR")
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
            logMicrophone("资产写入器为空，无法完成写入", level: "ERROR")
            return
        }
        
        logMicrophone("========== 录制完成统计 ==========")
        logMicrophone("视频帧总数: \(frameCount)")
        logMicrophone("系统音频帧总数: \(audioFrameCount) (失败: \(audioFailCount))")
        logMicrophone("麦克风音频帧总数: \(micFrameCount) (失败: \(micFailCount))", level: micFrameCount > 0 ? "SUCCESS" : "ERROR")
        
        // 检查 AVAssetWriter 的输入状态
        logMicrophone("========== AVAssetWriter 输入状态 ==========")
        logMicrophone("videoInput 存在: \(videoInput != nil)")
        logMicrophone("audioInput 存在: \(audioInput != nil)")
        logMicrophone("microphoneInput 存在: \(microphoneInput != nil)")
        logMicrophone("AVAssetWriter.inputs 数量: \(assetWriter.inputs.count)")
        
        for (index, input) in assetWriter.inputs.enumerated() {
            logMicrophone("  Input[\(index)]: mediaType=\(input.mediaType.rawValue), isReadyForMoreMediaData=\(input.isReadyForMoreMediaData)")
        }
        
        if micFrameCount == 0 {
            logMicrophone("⚠️ 警告：没有录制到任何麦克风音频帧！", level: "ERROR")
        }
        
        print("📝 开始完成录制写入...")
        print("  - 视频帧总数: \(frameCount)")
        print("  - 系统音频帧总数: \(audioFrameCount)")
        print("  - 麦克风音频帧总数: \(micFrameCount)")
        
        // 标记输入完成
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        microphoneInput?.markAsFinished()
        
        // 完成写入前检查状态
        logMicrophone("AVAssetWriter.status 在 finishWriting 前: \(assetWriter.status.rawValue)")
        if let error = assetWriter.error {
            logMicrophone("AVAssetWriter.error 在 finishWriting 前: \(error.localizedDescription)", level: "ERROR")
        }
        
        // 完成写入 - 捕获 outputURL 避免在回调中丢失
        let finalOutputURL = outputURL
        
        assetWriter.finishWriting {
            DispatchQueue.main.async {
                logMicrophone("AVAssetWriter.status 在 finishWriting 后: \(assetWriter.status.rawValue)")
                
                if let error = assetWriter.error {
                    print("✗ 录制完成时出错: \(error.localizedDescription)")
                    logMicrophone("✗ AVAssetWriter 完成时出错: \(error.localizedDescription)", level: "ERROR")
                    logMicrophone("  错误域: \(error._domain)", level: "ERROR")
                    logMicrophone("  错误代码: \(error._code)", level: "ERROR")
                } else {
                    print("✓ 录制成功完成，文件保存至: \(finalOutputURL.path)")
                    logMicrophone("✓ AVAssetWriter.finishWriting() 成功", level: "SUCCESS")
                    
                    // 验证文件是否存在且有效
                    logMicrophone("检查文件是否存在: \(finalOutputURL.path)")
                    let fileExists = FileManager.default.fileExists(atPath: finalOutputURL.path)
                    logMicrophone("文件存在性检查结果: \(fileExists)", level: fileExists ? "SUCCESS" : "ERROR")
                    
                    if fileExists {
                        do {
                            let attributes = try FileManager.default.attributesOfItem(atPath: finalOutputURL.path)
                            let fileSize = attributes[.size] as? Int64 ?? 0
                            print("录制文件大小: \(fileSize) 字节")
                            logMicrophone("录制文件大小: \(fileSize) 字节")
                            
                            if fileSize > 0 {
                                print("录制文件有效")
                                
                                // 使用 AVAsset 检查音频轨道
                                self.inspectVideoFile(url: finalOutputURL)
                            } else {
                                print("警告: 录制文件大小为0")
                                logMicrophone("警告: 录制文件大小为0", level: "WARN")
                            }
                        } catch {
                            print("无法获取文件属性: \(error)")
                            logMicrophone("无法获取文件属性: \(error.localizedDescription)", level: "ERROR")
                        }
                    } else {
                        print("错误: 录制文件不存在")
                        logMicrophone("✗ 错误: 录制文件不存在于路径: \(finalOutputURL.path)", level: "ERROR")
                        
                        // 检查父目录是否存在
                        let parentDir = finalOutputURL.deletingLastPathComponent()
                        let parentExists = FileManager.default.fileExists(atPath: parentDir.path)
                        logMicrophone("父目录存在性: \(parentExists) - \(parentDir.path)", level: parentExists ? "INFO" : "ERROR")
                        
                        // 列出父目录中的文件
                        if parentExists {
                            do {
                                let files = try FileManager.default.contentsOfDirectory(atPath: parentDir.path)
                                logMicrophone("父目录中的文件数量: \(files.count)")
                                for file in files.prefix(5) {
                                    logMicrophone("  - \(file)")
                                }
                            } catch {
                                logMicrophone("无法列出父目录内容: \(error.localizedDescription)", level: "ERROR")
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// 检查视频文件的音频轨道
    private func inspectVideoFile(url: URL) {
        let asset = AVAsset(url: url)
        
        logMicrophone("========== 视频文件轨道检查 ==========")
        logMicrophone("文件路径: \(url.path)")
        
        let videoTracks = asset.tracks(withMediaType: .video)
        let audioTracks = asset.tracks(withMediaType: .audio)
        
        logMicrophone("视频轨道数量: \(videoTracks.count)")
        logMicrophone("音频轨道数量: \(audioTracks.count)", level: audioTracks.count > 0 ? "SUCCESS" : "ERROR")
        
        if audioTracks.isEmpty {
            logMicrophone("⚠️ 警告：视频文件中没有音频轨道！", level: "ERROR")
            logMicrophone("可能原因：AVAssetWriter 不支持同时添加多个音频轨道", level: "ERROR")
        } else {
            for (index, track) in audioTracks.enumerated() {
                logMicrophone("音频轨道[\(index)]:")
                if let formatDescriptions = track.formatDescriptions as? [CMFormatDescription], let formatDesc = formatDescriptions.first {
                    if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                        logMicrophone("  - 采样率: \(asbd.pointee.mSampleRate)Hz")
                        logMicrophone("  - 声道数: \(asbd.pointee.mChannelsPerFrame)")
                    }
                }
            }
        }
        
        logMicrophone("========================================")
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

// MARK: - Microphone Debug Logger

/// 麦克风调试日志函数
fileprivate func logMicrophone(_ message: String, level: String = "INFO") {
    let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    let logFileURL = desktopURL.appendingPathComponent("MacScreenCapture_Microphone_Debug.log")
    
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let timestamp = dateFormatter.string(from: Date())
    let logMessage = "[\(timestamp)] [\(level)] \(message)\n"
    
    print("🎤 \(logMessage.trimmingCharacters(in: .newlines))")
    
    DispatchQueue.global(qos: .utility).async {
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }
}