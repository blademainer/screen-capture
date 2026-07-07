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
@preconcurrency import Vision

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
    private var colorSampler: NSColorSampler?

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
        let sliceCount = max(2, UserDefaults.standard.integer(forKey: "scrollingCaptureSlices"))
        let delay = max(0.2, UserDefaults.standard.double(forKey: "scrollingCaptureDelay"))
        let scrollLines = max(3, UserDefaults.standard.integer(forKey: "scrollingCaptureLines"))
        let trimOverlap = UserDefaults.standard.object(forKey: "scrollingCaptureTrimOverlap") as? Bool ?? true

        let alert = NSAlert()
        alert.messageText = "长截图助手"
        alert.informativeText = "请把鼠标放到需要滚动的窗口上。应用会截取 \(sliceCount) 屏，每屏之间自动向下滚动并拼接成长图。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "开始")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            var images: [NSImage] = []

            for index in 0..<sliceCount {
                if index > 0 {
                    scrollActiveView(lines: scrollLines)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }

                let image = try await captureDisplayImageWithoutSaving()
                images.append(image)
            }

            let stitchedImage = stitchImagesVertically(images, trimOverlap: trimOverlap)
            try await finalizeCapturedImage(stitchedImage, showEditor: true)
        } catch {
            showAlert(title: "长截图失败", message: error.localizedDescription)
        }
    }

    /// 延时截图
    @MainActor
    func captureDelayedScreenshot(seconds: Int? = nil) async throws -> NSImage {
        let delay = seconds ?? max(1, UserDefaults.standard.integer(forKey: "delayedScreenshotSeconds"))
        try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
        return try await captureScreenshot()
    }

    /// 多窗口截图 - 使用 macOS 系统交互选择窗口，按住 Shift 可连续选择多个窗口。
    @MainActor
    func captureMultipleWindowsScreenshot() async throws -> NSImage {
        return try await captureInteractiveScreenshot(arguments: ["-i", "-W"], showEditor: true)
    }

    /// 全屏带壳截图
    @MainActor
    func captureDeviceFramedFullScreen() async throws -> NSImage {
        let image = try await captureDisplayImageWithoutSaving()
        let framedImage = renderDeviceFrame(around: image)
        try await finalizeCapturedImage(framedImage, forceStyle: false, showEditor: true)
        return framedImage
    }

    /// 取色
    @MainActor
    func pickScreenColor() {
        colorSampler = NSColorSampler()
        colorSampler?.show { [weak self] color in
            Task { @MainActor in
                guard let self = self, let color = color else { return }
                let code = self.formattedColorCode(for: color)
                let name = self.approximateColorName(for: color)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
                self.showAlert(title: "取色完成", message: "颜色：\(name)\n已复制颜色值：\(code)")
                self.colorSampler = nil
            }
        }
    }

    /// OCR 当前最后一张截图
    @MainActor
    func recognizeTextFromLastScreenshot() async throws -> String {
        guard let image = lastCapturedImage else {
            throw CaptureError.noImageAvailable
        }

        let text = try await recognizeText(in: image)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return text
    }

    /// OCR 后翻译并显示结果
    @MainActor
    func translateLastScreenshot() async throws -> ScreenshotTranslationResult {
        let text = try await recognizeTextFromLastScreenshot()
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw CaptureError.noRecognizedText
        }

        let targetLanguage = UserDefaults.standard.string(forKey: "translationTargetLanguage") ?? "zh-CN"
        let translatedText = try await translateText(trimmedText, targetLanguage: targetLanguage)
        let result = ScreenshotTranslationResult(
            sourceText: trimmedText,
            translatedText: translatedText,
            targetLanguage: targetLanguage
        )

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translatedText, forType: .string)
        showTranslationWindow(result)

        return result
    }

    @MainActor
    func openWebTranslation(for text: String) throws {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.google.com/?sl=auto&tl=zh-CN&text=\(encoded)&op=translate") else {
            throw CaptureError.failedToTranslate
        }

        NSWorkspace.shared.open(url)
    }

    /// 使用用户指定的 App 打开最近一次保存的截图。
    @MainActor
    func openLastScreenshotInConfiguredApp() throws {
        guard let imageURL = lastSavedImageURL else {
            throw CaptureError.noImageAvailable
        }

        if let appPath = UserDefaults.standard.string(forKey: "openAfterCaptureAppPath"), !appPath.isEmpty {
            let appURL = URL(fileURLWithPath: appPath)
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([imageURL], withApplicationAt: appURL, configuration: configuration)
        } else {
            NSWorkspace.shared.open(imageURL)
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
        configuration.showsCursor = UserDefaults.standard.bool(forKey: "showCursor")

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return try await finalizeCapturedImage(nsImage, showEditor: false)
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

        let startDelay = UserDefaults.standard.integer(forKey: "recordingStartDelaySeconds")
        if startDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(startDelay) * 1_000_000_000)
        }

        let selectedRecordingRegion: CGRect?
        if captureMode == .region {
            selectedRecordingRegion = try await selectRecordingRegion()
        } else {
            selectedRecordingRegion = nil
        }

        // 通知WindowManager开始录制
        WindowManager.shared.updateCaptureState(.recording(startTime: Date()))

        // 在后台队列中执行耗时操作
        let (filter, screenSize, outputURL, sourceRect): (SCContentFilter, CGSize, URL, CGRect?) = try await withCheckedThrowingContinuation { continuation in
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
                                guard let region = selectedRecordingRegion,
                                      let display = content.displays.first(where: { $0.frame.intersects(region) }) ?? content.displays.first else {
                                    captureError = CaptureError.noDisplayAvailable
                                    return
                                }
                                filter = SCContentFilter(display: display, excludingWindows: [])
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
                            if case .region = self.captureMode, let region = selectedRecordingRegion {
                                return region.size
                            } else if case .fullScreen = self.captureMode, let display = self.selectedDisplay ?? content.displays.first {
                                return CGSize(width: display.width, height: display.height)
                            } else {
                                // 默认使用主屏幕分辨率
                                let mainScreen = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
                                return mainScreen
                            }
                        }

                        // 创建输出文件URL
                        let recordingFormat = UserDefaults.standard.string(forKey: "recordingFileFormat") ?? "MOV"
                        let fileExtension = recordingFormat.lowercased()
                        let fileName = "Recording_\(DateFormatter.fileNameFormatter.string(from: Date())).\(fileExtension)"
                        let outputURL = await MainActor.run {
                            self.outputDirectory.appendingPathComponent(fileName)
                        }

                        continuation.resume(returning: (finalFilter, screenSize, outputURL, selectedRecordingRegion))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        let configuration = SCStreamConfiguration()
        configuration.width = Int(screenSize.width)
        configuration.height = Int(screenSize.height)
        let frameRate = max(15, Int(UserDefaults.standard.double(forKey: "recordingFrameRate")))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange // 使用 YUV 格式，更适合 H.264
        configuration.showsCursor = UserDefaults.standard.bool(forKey: "showCursor")
        configuration.queueDepth = 5
        configuration.colorSpaceName = CGColorSpace.sRGB // 使用标准 sRGB 色彩空间
        if let sourceRect = sourceRect {
            configuration.sourceRect = sourceRect
        }

        // 根据用户设置决定是否录制音频
        let includeSystemAudio = UserDefaults.standard.bool(forKey: "includeSystemAudio")
        let includeMicrophone = UserDefaults.standard.bool(forKey: "includeMicrophone")

        configuration.capturesAudio = includeSystemAudio
        configuration.captureMicrophone = includeMicrophone

        logMicrophone("SCStreamConfiguration 配置:")
        logMicrophone("  - capturesAudio: \(includeSystemAudio)")
        logMicrophone("  - captureMicrophone: \(includeMicrophone)", level: includeMicrophone ? "SUCCESS" : "WARN")

        print("音频录制设置 - 系统音频: \(includeSystemAudio), 麦克风: \(includeMicrophone)")

        print("录制配置: \(Int(screenSize.width))x\(Int(screenSize.height)) @ \(frameRate)fps")

        recordingURL = outputURL
        print("录制文件路径: \(recordingURL!.path)")

        // 创建流输出
        let fileType: AVFileType = (UserDefaults.standard.string(forKey: "recordingFileFormat") == "MP4") ? .mp4 : .mov
        streamOutput = CaptureStreamOutput(outputURL: recordingURL!, fileType: fileType)

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
            UserDefaults.standard.set(0, forKey: "recordingStartDelaySeconds")
            UserDefaults.standard.set("MOV", forKey: "recordingFileFormat")
            UserDefaults.standard.set(true, forKey: "hasSetupDefaultRecordingSettings")

            print("已设置默认录制设置 - 麦克风录制已启用")
        }

        if !UserDefaults.standard.bool(forKey: "hasSetupDefaultAdvancedCaptureSettings") {
            UserDefaults.standard.set(5, forKey: "delayedScreenshotSeconds")
            UserDefaults.standard.set(5, forKey: "scrollingCaptureSlices")
            UserDefaults.standard.set(0.8, forKey: "scrollingCaptureDelay")
            UserDefaults.standard.set(12, forKey: "scrollingCaptureLines")
            UserDefaults.standard.set(true, forKey: "scrollingCaptureTrimOverlap")
            UserDefaults.standard.set("#HEX", forKey: "colorCodeFormat")
            UserDefaults.standard.set(false, forKey: "screenshotRoundedCorners")
            UserDefaults.standard.set(false, forKey: "screenshotDropShadow")
            UserDefaults.standard.set(18.0, forKey: "screenshotCornerRadius")
            UserDefaults.standard.set(24.0, forKey: "screenshotShadowRadius")
            UserDefaults.standard.set("#000000", forKey: "screenshotShadowColorHex")
            UserDefaults.standard.set(true, forKey: "hasSetupDefaultAdvancedCaptureSettings")
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
                            let finalImage = self.applyOutputStyle(to: image)

                            do {
                                try await self.saveScreenshot(finalImage)
                                self.lastCapturedImage = finalImage

                                // 显示编辑窗口
                                WindowManager.shared.showEditingWindow(for: finalImage)

                                // 清理临时文件
                                try? FileManager.default.removeItem(at: tempURL)

                                continuation.resume(returning: finalImage)
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

    /// 捕获当前显示器画面但不保存，供长截图、带壳截图等高级功能复用。
    private func captureDisplayImageWithoutSaving() async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = selectedDisplay ?? content.displays.first else {
            throw CaptureError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(display.width)
        configuration.height = Int(display.height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    @MainActor
    private func selectRecordingRegion() async throws -> CGRect {
        guard let screen = NSScreen.main else {
            throw CaptureError.noDisplayAvailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let selectionWindow = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            selectionWindow.level = .screenSaver
            selectionWindow.backgroundColor = .clear
            selectionWindow.isOpaque = false
            selectionWindow.hasShadow = false
            selectionWindow.ignoresMouseEvents = false
            selectionWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let overlayView = RecordingRegionSelectionView(screenFrame: screen.frame) { result in
                guard !didResume else { return }
                didResume = true
                selectionWindow.contentView = nil
                selectionWindow.close()

                switch result {
                case .success(let rect):
                    continuation.resume(returning: rect)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            selectionWindow.contentView = overlayView
            selectionWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// 使用系统 screencapture 交互选择并保存结果。
    @MainActor
    private func captureInteractiveScreenshot(arguments: [String], showEditor: Bool) async throws -> NSImage {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("interactive_capture_\(UUID().uuidString).png")
        process.arguments = arguments + [tempURL.path]

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                Task { @MainActor in
                    if process.terminationStatus == 0, let image = NSImage(contentsOf: tempURL) {
                        do {
                            let finalImage = try await self.finalizeCapturedImage(image, showEditor: showEditor)
                            try? FileManager.default.removeItem(at: tempURL)
                            continuation.resume(returning: finalImage)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    } else {
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

    @discardableResult
    private func finalizeCapturedImage(_ image: NSImage, forceStyle: Bool = true, showEditor: Bool) async throws -> NSImage {
        let finalImage = forceStyle ? applyOutputStyle(to: image) : image
        try await saveScreenshot(finalImage)

        await MainActor.run {
            lastCapturedImage = finalImage
            if showEditor {
                WindowManager.shared.showEditingWindow(for: finalImage)
            }
        }

        return finalImage
    }

    private func applyOutputStyle(to image: NSImage) -> NSImage {
        var currentImage = image

        if UserDefaults.standard.bool(forKey: "screenshotRoundedCorners") {
            let radius = CGFloat(UserDefaults.standard.double(forKey: "screenshotCornerRadius"))
            currentImage = renderRoundedImage(currentImage, radius: radius)
        }

        if UserDefaults.standard.bool(forKey: "screenshotDropShadow") {
            let radius = CGFloat(UserDefaults.standard.double(forKey: "screenshotShadowRadius"))
            let shadowColor = colorFromHex(UserDefaults.standard.string(forKey: "screenshotShadowColorHex") ?? "#000000") ?? .black
            currentImage = renderShadowedImage(currentImage, shadowRadius: radius, shadowColor: shadowColor)
        }

        return currentImage
    }

    private func renderRoundedImage(_ image: NSImage, radius: CGFloat) -> NSImage {
        let output = NSImage(size: image.size)
        output.lockFocus()

        let rect = NSRect(origin: .zero, size: image.size)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        path.addClip()
        image.draw(in: rect)

        output.unlockFocus()
        return output
    }

    private func renderShadowedImage(_ image: NSImage, shadowRadius: CGFloat, shadowColor: NSColor) -> NSImage {
        let padding = max(24, shadowRadius * 2)
        let outputSize = NSSize(width: image.size.width + padding * 2, height: image.size.height + padding * 2)
        let output = NSImage(size: outputSize)

        output.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: outputSize).fill()

        let shadow = NSShadow()
        shadow.shadowBlurRadius = shadowRadius
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.shadowColor = shadowColor.withAlphaComponent(0.28)
        shadow.set()

        let imageRect = NSRect(x: padding, y: padding, width: image.size.width, height: image.size.height)
        NSColor.white.setFill()
        NSBezierPath(rect: imageRect).fill()
        image.draw(in: imageRect)

        output.unlockFocus()
        return output
    }

    private func renderDeviceFrame(around image: NSImage) -> NSImage {
        let bezel: CGFloat = 42
        let titleBar: CGFloat = 34
        let padding: CGFloat = 48
        let frameSize = NSSize(
            width: image.size.width + bezel * 2 + padding * 2,
            height: image.size.height + bezel * 2 + titleBar + padding * 2
        )
        let output = NSImage(size: frameSize)

        output.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: frameSize).fill()

        let bodyRect = NSRect(
            x: padding,
            y: padding,
            width: image.size.width + bezel * 2,
            height: image.size.height + bezel * 2 + titleBar
        )

        let shadow = NSShadow()
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
        shadow.set()

        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        NSBezierPath(roundedRect: bodyRect, xRadius: 26, yRadius: 26).fill()

        NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
        let screenRect = NSRect(
            x: bodyRect.minX + bezel,
            y: bodyRect.minY + bezel,
            width: image.size.width,
            height: image.size.height
        )
        image.draw(in: screenRect)

        let cameraRect = NSRect(x: bodyRect.midX - 5, y: bodyRect.maxY - 22, width: 10, height: 10)
        NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
        NSBezierPath(ovalIn: cameraRect).fill()

        output.unlockFocus()
        return output
    }

    private func stitchImagesVertically(_ images: [NSImage], trimOverlap: Bool) -> NSImage {
        guard let first = images.first else { return NSImage(size: .zero) }
        let normalizedImages = trimOverlap ? removeOverlappingScrollRegions(from: images) : images
        let width = normalizedImages.map { $0.size.width }.min() ?? first.size.width
        let height = normalizedImages.reduce(CGFloat(0)) { $0 + ($1.size.height * width / max($1.size.width, 1)) }
        let output = NSImage(size: NSSize(width: width, height: height))

        output.lockFocus()
        var y = height
        for image in normalizedImages {
            let scaledHeight = image.size.height * width / max(image.size.width, 1)
            y -= scaledHeight
            image.draw(in: NSRect(x: 0, y: y, width: width, height: scaledHeight))
        }
        output.unlockFocus()

        return output
    }

    private func removeOverlappingScrollRegions(from images: [NSImage]) -> [NSImage] {
        guard images.count > 1 else { return images }

        var result: [NSImage] = []
        var previous = images[0]
        result.append(previous)

        for image in images.dropFirst() {
            let overlap = detectedVerticalOverlap(previous: previous, next: image)
            let cropped = cropTopPixels(overlap, from: image)
            result.append(cropped)
            previous = image
        }

        return result
    }

    private func detectedVerticalOverlap(previous: NSImage, next: NSImage) -> Int {
        guard let previousCG = previous.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let nextCG = next.cgImage(forProposedRect: nil, context: nil, hints: nil),
              previousCG.width == nextCG.width,
              previousCG.height == nextCG.height,
              let previousBuffer = rgbaBuffer(from: previousCG),
              let nextBuffer = rgbaBuffer(from: nextCG) else {
            return 0
        }

        let width = previousCG.width
        let height = previousCG.height
        let minOverlap = max(24, height / 20)
        let maxOverlap = max(minOverlap, height * 3 / 4)
        let step = max(4, height / 160)
        let sampleXStride = max(8, width / 96)
        let sampleYStride = max(4, height / 160)

        var bestOverlap = 0
        var bestScore = Double.greatestFiniteMagnitude

        for overlap in stride(from: minOverlap, through: maxOverlap, by: step) {
            var totalDifference = 0
            var samples = 0

            for y in stride(from: 0, to: overlap, by: sampleYStride) {
                let previousY = height - overlap + y
                let nextY = y

                for x in stride(from: 0, to: width, by: sampleXStride) {
                    let previousOffset = (previousY * width + x) * 4
                    let nextOffset = (nextY * width + x) * 4

                    totalDifference += abs(Int(previousBuffer[previousOffset]) - Int(nextBuffer[nextOffset]))
                    totalDifference += abs(Int(previousBuffer[previousOffset + 1]) - Int(nextBuffer[nextOffset + 1]))
                    totalDifference += abs(Int(previousBuffer[previousOffset + 2]) - Int(nextBuffer[nextOffset + 2]))
                    samples += 3
                }
            }

            guard samples > 0 else { continue }
            let score = Double(totalDifference) / Double(samples)

            if score < bestScore {
                bestScore = score
                bestOverlap = overlap
            }
        }

        // 低差异才裁剪，避免两个无关画面被误判为重叠。
        return bestScore < 16 ? bestOverlap : 0
    }

    private func rgbaBuffer(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private func cropTopPixels(_ pixels: Int, from image: NSImage) -> NSImage {
        guard pixels > 0,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              pixels < cgImage.height - 1 else {
            return image
        }

        let cropRect = CGRect(
            x: 0,
            y: pixels,
            width: cgImage.width,
            height: cgImage.height - pixels
        )

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return image
        }

        return NSImage(
            cgImage: croppedCGImage,
            size: NSSize(width: croppedCGImage.width, height: croppedCGImage.height)
        )
    }

    private func scrollActiveView(lines: Int) {
        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: -Int32(lines),
            wheel2: 0,
            wheel3: 0
        )
        event?.post(tap: .cghidEventTap)
    }

    private func formattedColorCode(for color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let red = Int(round(rgb.redComponent * 255))
        let green = Int(round(rgb.greenComponent * 255))
        let blue = Int(round(rgb.blueComponent * 255))
        let hex = String(format: "#%02X%02X%02X", red, green, blue)
        let format = UserDefaults.standard.string(forKey: "colorCodeFormat") ?? "#HEX"

        switch format {
        case "RGB":
            return "rgb(\(red), \(green), \(blue))"
        case "SwiftUI":
            return String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
        case "Custom":
            let template = UserDefaults.standard.string(forKey: "customColorCodeTemplate") ?? "{hex}"
            return template
                .replacingOccurrences(of: "{hex}", with: hex)
                .replacingOccurrences(of: "{r255}", with: "\(red)")
                .replacingOccurrences(of: "{g255}", with: "\(green)")
                .replacingOccurrences(of: "{b255}", with: "\(blue)")
                .replacingOccurrences(of: "{r}", with: String(format: "%.3f", rgb.redComponent))
                .replacingOccurrences(of: "{g}", with: String(format: "%.3f", rgb.greenComponent))
                .replacingOccurrences(of: "{b}", with: String(format: "%.3f", rgb.blueComponent))
        default:
            return hex
        }
    }

    private func approximateColorName(for color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let red = Int(round(rgb.redComponent * 255))
        let green = Int(round(rgb.greenComponent * 255))
        let blue = Int(round(rgb.blueComponent * 255))

        let palette: [(name: String, r: Int, g: Int, b: Int)] = [
            ("黑色", 0, 0, 0), ("白色", 255, 255, 255), ("灰色", 128, 128, 128),
            ("红色", 220, 38, 38), ("橙色", 249, 115, 22), ("黄色", 234, 179, 8),
            ("绿色", 34, 197, 94), ("青色", 6, 182, 212), ("蓝色", 59, 130, 246),
            ("矢车菊蓝", 100, 149, 237), ("紫色", 147, 51, 234), ("粉色", 236, 72, 153),
            ("棕色", 120, 72, 35), ("米色", 245, 245, 220), ("深蓝", 30, 64, 175)
        ]

        return palette.min { lhs, rhs in
            colorDistanceSquared(red, green, blue, lhs) < colorDistanceSquared(red, green, blue, rhs)
        }?.name ?? "未知颜色"
    }

    private func colorDistanceSquared(_ red: Int, _ green: Int, _ blue: Int, _ candidate: (name: String, r: Int, g: Int, b: Int)) -> Int {
        let dr = red - candidate.r
        let dg = green - candidate.g
        let db = blue - candidate.b
        return dr * dr + dg * dg + db * db
    }

    private func colorFromHex(_ hex: String) -> NSColor? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespacesAndNewlines))
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }
        return NSColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private func recognizeText(in image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CaptureError.failedToRecognizeText
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func translateText(_ text: String, targetLanguage: String) async throws -> String {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: targetLanguage),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]

        guard let url = components?.url else {
            throw CaptureError.failedToTranslate
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw CaptureError.failedToTranslate
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any],
              let translatedParts = root.first as? [Any] else {
            throw CaptureError.failedToTranslate
        }

        let translatedText = translatedParts.compactMap { item -> String? in
            guard let segment = item as? [Any] else { return nil }
            return segment.first as? String
        }
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !translatedText.isEmpty else {
            throw CaptureError.failedToTranslate
        }

        return translatedText
    }

    @MainActor
    private func showTranslationWindow(_ result: ScreenshotTranslationResult) {
        let controller = ScreenshotTranslationWindowController(result: result)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
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
    case noImageAvailable
    case noRecognizedText
    case failedToRecognizeText
    case failedToTranslate

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
        case .noImageAvailable:
            return "没有可识别的截图，请先截图"
        case .noRecognizedText:
            return "没有识别到可翻译的文字"
        case .failedToRecognizeText:
            return "OCR 识别失败"
        case .failedToTranslate:
            return "打开翻译失败"
        }
    }
}

// MARK: - Screenshot Translation

struct ScreenshotTranslationResult {
    let sourceText: String
    let translatedText: String
    let targetLanguage: String
}

final class ScreenshotTranslationWindowController: NSWindowController {
    private let result: ScreenshotTranslationResult

    init(result: ScreenshotTranslationResult) {
        self.result = result

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "截图翻译"
        window.minSize = NSSize(width: 560, height: 360)
        window.center()

        super.init(window: window)
        setupContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupContent() {
        guard let window = window else { return }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "截图翻译")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let targetLabel = NSTextField(labelWithString: "目标语言：\(result.targetLanguage)")
        targetLabel.textColor = .secondaryLabelColor
        targetLabel.translatesAutoresizingMaskIntoConstraints = false

        let sourceLabel = NSTextField(labelWithString: "OCR 原文")
        sourceLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false

        let translatedLabel = NSTextField(labelWithString: "译文")
        translatedLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        translatedLabel.translatesAutoresizingMaskIntoConstraints = false

        let sourceTextView = makeTextView(text: result.sourceText)
        let translatedTextView = makeTextView(text: result.translatedText)

        let copySourceButton = NSButton(title: "复制原文", target: self, action: #selector(copySourceText))
        copySourceButton.bezelStyle = .rounded
        copySourceButton.translatesAutoresizingMaskIntoConstraints = false

        let copyTranslatedButton = NSButton(title: "复制译文", target: self, action: #selector(copyTranslatedText))
        copyTranslatedButton.bezelStyle = .rounded
        copyTranslatedButton.translatesAutoresizingMaskIntoConstraints = false

        let openWebButton = NSButton(title: "网页翻译", target: self, action: #selector(openWebTranslation))
        openWebButton.bezelStyle = .rounded
        openWebButton.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(title: "关闭", target: self, action: #selector(closeWindow))
        closeButton.bezelStyle = .rounded
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        [titleLabel, targetLabel, sourceLabel, translatedLabel, sourceTextView, translatedTextView, copySourceButton, copyTranslatedButton, openWebButton, closeButton].forEach {
            container.addSubview($0)
        }

        window.contentView = container

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            targetLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            targetLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            sourceLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            sourceLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            translatedLabel.topAnchor.constraint(equalTo: sourceLabel.topAnchor),
            translatedLabel.leadingAnchor.constraint(equalTo: container.centerXAnchor, constant: 8),

            sourceTextView.topAnchor.constraint(equalTo: sourceLabel.bottomAnchor, constant: 8),
            sourceTextView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            sourceTextView.trailingAnchor.constraint(equalTo: container.centerXAnchor, constant: -8),
            sourceTextView.bottomAnchor.constraint(equalTo: copySourceButton.topAnchor, constant: -14),

            translatedTextView.topAnchor.constraint(equalTo: translatedLabel.bottomAnchor, constant: 8),
            translatedTextView.leadingAnchor.constraint(equalTo: container.centerXAnchor, constant: 8),
            translatedTextView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            translatedTextView.bottomAnchor.constraint(equalTo: copyTranslatedButton.topAnchor, constant: -14),

            copySourceButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            copySourceButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18),

            copyTranslatedButton.leadingAnchor.constraint(equalTo: sourceTextView.trailingAnchor, constant: 16),
            copyTranslatedButton.bottomAnchor.constraint(equalTo: copySourceButton.bottomAnchor),

            closeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            closeButton.bottomAnchor.constraint(equalTo: copySourceButton.bottomAnchor),

            openWebButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -10),
            openWebButton.bottomAnchor.constraint(equalTo: copySourceButton.bottomAnchor)
        ])
    }

    private func makeTextView(text: String) -> NSScrollView {
        let textView = NSTextView()
        textView.string = text
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 10, height: 10)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView
        return scrollView
    }

    @objc private func copySourceText() {
        copyToPasteboard(result.sourceText)
    }

    @objc private func copyTranslatedText() {
        copyToPasteboard(result.translatedText)
    }

    @objc private func openWebTranslation() {
        guard let encoded = result.sourceText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.google.com/?sl=auto&tl=\(result.targetLanguage)&text=\(encoded)&op=translate") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func closeWindow() {
        close()
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Recording Region Selection

@available(macOS 12.3, *)
final class RecordingRegionSelectionView: NSView {
    private let screenFrame: CGRect
    private let completion: (Result<CGRect, Error>) -> Void
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    init(screenFrame: CGRect, completion: @escaping (Result<CGRect, Error>) -> Void) {
        self.screenFrame = screenFrame
        self.completion = completion
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.34).setFill()
        bounds.fill()

        guard let rect = selectionRect else {
            drawInstruction()
            return
        }

        NSColor.clear.setFill()
        rect.fill(using: .clear)

        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        NSColor.systemBlue.setStroke()
        path.stroke()

        NSColor.systemBlue.withAlphaComponent(0.18).setFill()
        rect.fill()

        drawSizeLabel(for: rect)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)

        guard let rect = selectionRect, rect.width >= 16, rect.height >= 16 else {
            completion(.failure(CaptureError.regionSelectionCancelled))
            return
        }

        completion(.success(CGRect(
            x: screenFrame.origin.x + rect.origin.x,
            y: screenFrame.origin.y + rect.origin.y,
            width: rect.width,
            height: rect.height
        )))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            completion(.failure(CaptureError.regionSelectionCancelled))
        } else {
            super.keyDown(with: event)
        }
    }

    private var selectionRect: CGRect? {
        guard let startPoint = startPoint, let currentPoint = currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    private func drawInstruction() {
        let text = "拖拽选择录制区域，按 Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.45)
        ]
        let size = text.size(withAttributes: attributes)
        let rect = NSRect(
            x: bounds.midX - size.width / 2 - 12,
            y: bounds.midY - size.height / 2 - 8,
            width: size.width + 24,
            height: size.height + 16
        )
        NSColor.black.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        text.draw(at: CGPoint(x: rect.minX + 12, y: rect.minY + 8), withAttributes: attributes)
    }

    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width)) x \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let labelRect = NSRect(
            x: rect.minX,
            y: max(8, rect.minY - size.height - 12),
            width: size.width + 16,
            height: size.height + 8
        )
        NSColor.systemBlue.setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()
        text.draw(at: CGPoint(x: labelRect.minX + 8, y: labelRect.minY + 4), withAttributes: attributes)
    }
}

// MARK: - Stream Output

@available(macOS 12.3, *)
class CaptureStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    private let outputURL: URL
    private let fileType: AVFileType
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

    init(outputURL: URL, fileType: AVFileType = .mov) {
        self.outputURL = outputURL
        self.fileType = fileType
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

            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
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
