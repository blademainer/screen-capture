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
import ApplicationServices
@preconcurrency import Vision
import NaturalLanguage
import Translation

struct RecordingAudioDiagnostics: Sendable {
    let outputURL: URL
    let requestedSystemAudio: Bool
    let requestedMicrophone: Bool
    let videoFrameCount: Int
    let systemAudioFrameCount: Int
    let microphoneFrameCount: Int
    let systemAudioFailCount: Int
    let microphoneFailCount: Int
    let videoTrackCount: Int
    let audioTrackCount: Int
    let fileSize: Int64
    let assetWriterSucceeded: Bool

    var requestedAnyAudio: Bool {
        requestedSystemAudio || requestedMicrophone
    }

    var hasAudioIssue: Bool {
        guard requestedAnyAudio else { return false }
        if !assetWriterSucceeded || audioTrackCount == 0 { return true }
        if requestedSystemAudio && systemAudioFrameCount == 0 { return true }
        if requestedMicrophone && microphoneFrameCount == 0 { return true }
        return false
    }

    var summaryText: String {
        var parts: [String] = []
        if requestedSystemAudio {
            parts.append("系统音频 \(systemAudioFrameCount) 帧")
        }
        if requestedMicrophone {
            parts.append("麦克风 \(microphoneFrameCount) 帧")
        }
        if parts.isEmpty {
            return "静音录制"
        }
        return parts.joined(separator: "，")
    }
}

/// 捕获管理器 - 负责截图和录制功能的核心逻辑
@available(macOS 12.3, *)
class CaptureManager: ObservableObject {

    // MARK: - Singleton
    static let shared = CaptureManager()

    // MARK: - Published Properties
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var isAudioOnlyRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var captureMode: CaptureMode = .fullScreen
    @Published var selectedDisplay: SCDisplay?
    @Published var selectedWindow: SCWindow?
    @Published var availableDisplays: [SCDisplay] = []
    @Published var availableWindows: [SCWindow] = []
    @Published var lastCapturedImage: NSImage?
    @Published var lastSavedImageURL: URL?
    @Published var recordingURL: URL?
    @Published var lastRecordingAudioDiagnostics: RecordingAudioDiagnostics?

    // MARK: - Private Properties
    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var securityScopedURL: URL?
    private var colorSampler: NSColorSampler?

    private struct ScrollingCaptureTarget {
        let display: SCDisplay
        let cropRect: CGRect
        let source: ScrollingCaptureTargetSource
    }

    private enum ScrollingCaptureTargetSource {
        case accessibilityContentArea
        case window
    }

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
            _ = try await captureInteractiveWindowScreenshot()
        } catch {
            print("窗口截图失败: \(error)")
        }
    }

    @discardableResult
    @MainActor
    func startRecordingWithPreflight() async throws -> Bool {
        guard !isRecording else { return false }
        guard confirmRecordingPreflight(audioOnly: false) else { return false }
        try await startRecording()
        return true
    }

    @discardableResult
    @MainActor
    func startAudioRecordingWithPreflight() async throws -> Bool {
        guard !isRecording else { return false }
        guard confirmRecordingPreflight(audioOnly: true) else { return false }
        try await startAudioRecording()
        return true
    }

    /// 滚动截图 - 快捷键调用
    @MainActor
    func captureScrollingWindow() async {
        let sliceCount = max(2, UserDefaults.standard.integer(forKey: "scrollingCaptureSlices"))
        let delay = max(0.2, UserDefaults.standard.double(forKey: "scrollingCaptureDelay"))
        let scrollLines = max(3, UserDefaults.standard.integer(forKey: "scrollingCaptureLines"))
        let trimOverlap = UserDefaults.standard.object(forKey: "scrollingCaptureTrimOverlap") as? Bool ?? true
        let cropToWindow = UserDefaults.standard.object(forKey: "scrollingCaptureCropToWindow") as? Bool ?? true
        let stopWhenUnchanged = UserDefaults.standard.object(forKey: "scrollingCaptureStopWhenUnchanged") as? Bool ?? true
        let scrollDirection = UserDefaults.standard.string(forKey: "scrollingCaptureDirection") == "up" ? "up" : "down"
        let directionLabel = scrollDirection == "up" ? "向上" : "向下"

        let alert = NSAlert()
        alert.messageText = "长截图助手"
        alert.informativeText = "点击开始后，请在 1 秒内把鼠标放到需要滚动的窗口上。应用最多截取 \(sliceCount) 屏，每屏之间自动\(directionLabel)滚动并拼接成长图；滚动到底会提前停止。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "开始")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            var images: [NSImage] = []
            var target: ScrollingCaptureTarget?

            if cropToWindow {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                target = scrollingCaptureTargetUnderMouse(from: content)
            }

            for index in 0..<sliceCount {
                if index > 0 {
                    scrollActiveView(lines: scrollLines, direction: scrollDirection)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }

                let image = try await captureDisplayImageWithoutSaving(display: target?.display)
                let sliceImage: NSImage
                if let target {
                    sliceImage = cropDisplayImage(image, to: target.cropRect, in: target.display)
                } else {
                    sliceImage = image
                }

                if stopWhenUnchanged,
                   let previous = images.last,
                   imagesAreVisuallySimilar(previous, sliceImage) {
                    break
                }

                images.append(sliceImage)
            }

            let orderedImages = scrollDirection == "up" ? Array(images.reversed()) : images
            let stitchedImage = stitchImagesVertically(orderedImages, trimOverlap: trimOverlap)
            try await finalizeCapturedImage(stitchedImage, showEditor: true)
        } catch {
            showAlert(title: "长截图失败", message: error.localizedDescription)
        }
    }

    /// 延时截图
    @MainActor
    func captureDelayedScreenshot(seconds: Int? = nil) async throws -> NSImage {
        let delay = seconds ?? max(1, UserDefaults.standard.integer(forKey: "delayedScreenshotSeconds"))
        let countdownOverlay = ScreenshotCountdownOverlayController()

        defer {
            countdownOverlay.close()
        }

        for remaining in stride(from: delay, through: 1, by: -1) {
            countdownOverlay.show(remaining: remaining)
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        countdownOverlay.close()
        try await Task.sleep(nanoseconds: 160_000_000)
        return try await captureScreenshot()
    }

    /// 多窗口截图 - 使用 macOS 系统交互选择窗口，按住 Shift 可连续选择多个窗口。
    @MainActor
    func captureMultipleWindowsScreenshot() async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayBounds = allDisplayBounds(from: content.displays)
        guard !displayBounds.isNull else {
            throw CaptureError.noDisplayAvailable
        }

        let currentPID = Int(ProcessInfo.processInfo.processIdentifier)
        let candidates = content.windows.filter { window in
            window.owningApplication?.processID != pid_t(currentPID) &&
            window.title?.isEmpty == false &&
            window.frame.width > 80 &&
            window.frame.height > 80 &&
            window.frame.intersects(displayBounds)
        }

        let selection = try await selectMultipleWindows(from: candidates, displayBounds: displayBounds)
        let useDesktopBackdrop = (UserDefaults.standard.object(forKey: "multiWindowDesktopBackdrop") as? Bool ?? true) || selection.usesDesktopBackdrop
        let composite = try await renderMultiWindowComposite(
            selection.windows,
            displays: content.displays,
            allWindows: content.windows,
            useDesktopBackdrop: useDesktopBackdrop
        )
        return try await finalizeCapturedImage(composite, showEditor: true)
    }

    /// 交互式窗口截图：普通点击立即截取单窗口，Shift 点击可连续选择多个窗口后合成。
    @MainActor
    func captureInteractiveWindowScreenshot() async throws -> NSImage {
        WindowManager.shared.updateCaptureState(.screenshotting)

        defer {
            WindowManager.shared.updateCaptureState(.idle)
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayBounds = allDisplayBounds(from: content.displays)
        guard !displayBounds.isNull else {
            throw CaptureError.noDisplayAvailable
        }

        let currentPID = Int(ProcessInfo.processInfo.processIdentifier)
        let candidates = content.windows.filter { window in
            window.owningApplication?.processID != pid_t(currentPID) &&
            window.title?.isEmpty == false &&
            window.frame.width > 80 &&
            window.frame.height > 80 &&
            window.frame.intersects(displayBounds)
        }

        let selection = try await selectMultipleWindows(
            from: candidates,
            displayBounds: displayBounds,
            singleClickCompletes: true
        )

        if selection.windows.count == 1, let window = selection.windows.first, !selection.usesDesktopBackdrop {
            let image = try await captureWindowImage(window)
            return try await finalizeCapturedImage(image, showEditor: false)
        }

        let useDesktopBackdrop = (UserDefaults.standard.object(forKey: "multiWindowDesktopBackdrop") as? Bool ?? true) || selection.usesDesktopBackdrop
        let composite = try await renderMultiWindowComposite(
            selection.windows,
            displays: content.displays,
            allWindows: content.windows,
            useDesktopBackdrop: useDesktopBackdrop
        )
        return try await finalizeCapturedImage(composite, showEditor: true)
    }

    /// 贴图 - 交互选择区域后打开置顶浮窗，可重复创建多个贴图。
    @MainActor
    func capturePinnedRegion() async throws -> NSImage {
        let image = try await captureInteractiveScreenshot(arguments: ["-i", "-r"], showEditor: false, autoOpenAfterCapture: false)
        FloatingWindowManager.shared.showFloatingPreview(for: image)
        return image
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

        return try await recognizeTextAndCopy(from: image)
    }

    /// 框选截图区域后直接 OCR 并复制文本，覆盖截图工具的 OCR 直达流程。
    @MainActor
    func captureRegionAndRecognizeText() async throws -> String {
        let image = try await captureInteractiveScreenshot(arguments: ["-i", "-r"], forceStyle: false, showEditor: false, autoOpenAfterCapture: false)
        return try await recognizeTextAndCopy(from: image)
    }

    @MainActor
    private func recognizeTextAndCopy(from image: NSImage) async throws -> String {
        let text = try await recognizeText(in: image)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return text
    }

    /// OCR 后翻译并显示结果
    @MainActor
    func translateLastScreenshot() async throws -> ScreenshotTranslationResult {
        guard let image = lastCapturedImage else {
            throw CaptureError.noImageAvailable
        }

        return try await translateScreenshotImage(image)
    }

    /// 框选截图区域后直接 OCR 并翻译，覆盖 iShot 的截图翻译直达流程。
    @MainActor
    func captureRegionAndTranslate() async throws -> ScreenshotTranslationResult {
        let image = try await captureInteractiveScreenshot(arguments: ["-i", "-r"], forceStyle: false, showEditor: false, autoOpenAfterCapture: false)
        return try await translateScreenshotImage(image)
    }

    @MainActor
    private func translateScreenshotImage(_ image: NSImage) async throws -> ScreenshotTranslationResult {
        let text = try await recognizeText(in: image)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw CaptureError.noRecognizedText
        }

        let targetLanguage = UserDefaults.standard.string(forKey: "translationTargetLanguage") ?? "zh-CN"
        let result: ScreenshotTranslationResult
        do {
            let translation = try await translateText(trimmedText, targetLanguage: targetLanguage)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(translation.text, forType: .string)
            result = ScreenshotTranslationResult(
                sourceText: trimmedText,
                translatedText: translation.text,
                targetLanguage: targetLanguage,
                providerName: translation.providerName,
                usedWebFallback: false
            )
        } catch {
            try openWebTranslation(for: trimmedText, targetLanguage: targetLanguage)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(trimmedText, forType: .string)
            result = ScreenshotTranslationResult(
                sourceText: trimmedText,
                translatedText: "在线翻译服务暂不可用，已打开网页翻译页面。原文已复制到剪贴板，可直接粘贴使用。",
                targetLanguage: targetLanguage,
                providerName: "网页翻译",
                usedWebFallback: true
            )
        }

        showTranslationWindow(result)

        return result
    }

    @MainActor
    func openWebTranslation(for text: String) throws {
        let targetLanguage = UserDefaults.standard.string(forKey: "translationTargetLanguage") ?? "zh-CN"
        try openWebTranslation(for: text, targetLanguage: targetLanguage)
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

    /// 区域截图并立即用用户指定的 App 打开，匹配 iShot 的双击 Option 连贯操作。
    @MainActor
    func captureRegionAndOpenInConfiguredApp() async throws -> NSImage {
        let originalMode = captureMode
        captureMode = .region
        defer { captureMode = originalMode }

        let image = try await captureScreenshot(autoOpenAfterCapture: false, forceSave: true)
        try openLastScreenshotInConfiguredApp()
        return image
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
                        if let currentOutput {
                            currentOutput.finishWriting { _ in
                                continuation.resume()
                            }
                        } else {
                            continuation.resume()
                        }
                    }
                } else {
                    if let currentOutput {
                        currentOutput.finishWriting { _ in
                            continuation.resume()
                        }
                    } else {
                        continuation.resume()
                    }
                }
            }
        }

        // 清理资源
        stream = nil
        streamOutput = nil
    }

    /// 截图
    func captureScreenshot(autoOpenAfterCapture: Bool = true, forceSave: Bool = false) async throws -> NSImage {
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
            return try await captureRegionScreenshot(autoOpenAfterCapture: autoOpenAfterCapture, forceSave: forceSave)
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
        return try await finalizeCapturedImage(nsImage, showEditor: false, autoOpenAfterCapture: autoOpenAfterCapture, forceSave: forceSave)
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

        let selectedRecordingRegion: CGRect?
        if captureMode == .region {
            selectedRecordingRegion = try await selectRecordingRegion()
        } else {
            selectedRecordingRegion = nil
        }

        try await waitForRecordingStartDelayIfNeeded(subtitle: "准备录制")

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
        let frameRate = min(60, max(15, Int(UserDefaults.standard.double(forKey: "recordingFrameRate"))))
        let recordingQuality = UserDefaults.standard.string(forKey: "recordingQuality") ?? "高"
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

        print("录制配置: \(Int(screenSize.width))x\(Int(screenSize.height)) @ \(frameRate)fps, 质量: \(recordingQuality)")

        recordingURL = outputURL
        print("录制文件路径: \(recordingURL!.path)")

        // 创建流输出
        let fileType: AVFileType = (UserDefaults.standard.string(forKey: "recordingFileFormat") == "MP4") ? .mp4 : .mov
        streamOutput = CaptureStreamOutput(
            outputURL: recordingURL!,
            fileType: fileType,
            includeSystemAudio: includeSystemAudio,
            includeMicrophone: includeMicrophone,
            frameRate: frameRate,
            quality: recordingQuality
        )

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

    /// 开始独立录音，覆盖 iShot Pro 的录音场景：可同时录制系统内部声音和麦克风。
    @MainActor
    func startAudioRecording() async throws {
        guard !isRecording else { return }

        let includeSystemAudio = UserDefaults.standard.bool(forKey: "includeSystemAudio")
        let includeMicrophonePreference = UserDefaults.standard.bool(forKey: "includeMicrophone")

        guard includeSystemAudio || includeMicrophonePreference else {
            throw CaptureError.recordingFailed("请至少开启系统音频或麦克风录音")
        }

        if includeMicrophonePreference {
            let permissionManager = PermissionManager()
            let deviceAvailable = permissionManager.checkMicrophoneDeviceAvailable()

            if !deviceAvailable {
                let shouldContinue = await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "未检测到麦克风"
                    alert.informativeText = "系统未检测到可用的麦克风设备，将仅录制系统音频。"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "继续")
                    alert.addButton(withTitle: "取消")
                    return alert.runModal() != .alertSecondButtonReturn
                }

                if !shouldContinue {
                    throw CaptureError.noMicrophoneAvailable
                }
            }

            let hasPermission = await permissionManager.requestMicrophonePermissionAsync()
            if !hasPermission {
                let shouldContinue = await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "麦克风权限未授予"
                    alert.informativeText = "无法录制麦克风音频，将仅录制系统音频。是否继续？"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "继续")
                    alert.addButton(withTitle: "取消")
                    return alert.runModal() != .alertSecondButtonReturn
                }

                if !shouldContinue {
                    throw CaptureError.microphonePermissionDenied
                }
                UserDefaults.standard.set(false, forKey: "includeMicrophone")
            }
        }

        let includeMicrophone = UserDefaults.standard.bool(forKey: "includeMicrophone")
        guard includeSystemAudio || includeMicrophone else {
            throw CaptureError.recordingFailed("没有可用的录音来源")
        }

        try await waitForRecordingStartDelayIfNeeded(subtitle: "准备录音")

        let (filter, outputURL): (SCContentFilter, URL) = try await withCheckedThrowingContinuation { continuation in
            captureQueue.async {
                Task {
                    do {
                        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                        guard let display = content.displays.first else {
                            continuation.resume(throwing: CaptureError.noDisplayAvailable)
                            return
                        }

                        let fileName = "Audio_\(DateFormatter.fileNameFormatter.string(from: Date())).m4a"
                        let outputURL = await MainActor.run {
                            self.outputDirectory.appendingPathComponent(fileName)
                        }

                        continuation.resume(returning: (SCContentFilter(display: display, excludingWindows: []), outputURL))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.capturesAudio = includeSystemAudio
        configuration.captureMicrophone = includeMicrophone
        configuration.queueDepth = 3

        recordingURL = outputURL
        streamOutput = CaptureStreamOutput(
            outputURL: outputURL,
            fileType: .m4a,
            includeSystemAudio: includeSystemAudio,
            includeMicrophone: includeMicrophone,
            frameRate: 1,
            quality: "音频",
            audioOnly: true
        )

        stream = SCStream(filter: filter, configuration: configuration, delegate: streamOutput)

        if includeSystemAudio {
            try stream?.addStreamOutput(streamOutput!, type: .audio, sampleHandlerQueue: captureQueue)
            logMicrophone("✓ 已添加独立录音系统音频流输出", level: "SUCCESS")
        }

        if includeMicrophone {
            try stream?.addStreamOutput(streamOutput!, type: .microphone, sampleHandlerQueue: captureQueue)
            logMicrophone("✓ 已添加独立录音麦克风流输出", level: "SUCCESS")
        }

        try await stream?.startCapture()

        let startTime = Date()
        isRecording = true
        isAudioOnlyRecording = true
        isPaused = false
        recordingStartTime = startTime
        startRecordingTimer()
        WindowManager.shared.updateCaptureState(.recording(startTime: startTime))

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
        let wasAudioOnlyRecording = isAudioOnlyRecording

        let completedDuration = recordingDuration
        let diagnostics: RecordingAudioDiagnostics? = await withCheckedContinuation { continuation in
            captureQueue.async {
                // 停止捕获流
                if let stream = currentStream {
                    stream.stopCapture { _ in
                        // 完成视频写入
                        if let currentOutput {
                            currentOutput.finishWriting { diagnostics in
                                continuation.resume(returning: diagnostics)
                            }
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }
                } else {
                    if let currentOutput {
                        currentOutput.finishWriting { diagnostics in
                            continuation.resume(returning: diagnostics)
                        }
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }

        // 更新状态
        isRecording = false
        isAudioOnlyRecording = false
        isPaused = false
        recordingDuration = 0
        recordingStartTime = nil

        // 通知WindowManager录制停止
        WindowManager.shared.updateCaptureState(.idle)

        // 清理资源
        stream = nil
        streamOutput = nil

        if let diagnostics {
            lastRecordingAudioDiagnostics = diagnostics
            showRecordingCompletionNotification(diagnostics: diagnostics, duration: completedDuration, audioOnly: wasAudioOnlyRecording)
        }

        print("录制已停止")

        // 发送通知
        NotificationCenter.default.post(
            name: .recordingDidStop,
            object: currentURL,
            userInfo: diagnostics.map { ["audioDiagnostics": $0] }
        )
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
            streamOutput?.setPaused(false)
            WindowManager.shared.updateCaptureState(.recording(startTime: recordingStartTime!))
        } else {
            // 暂停录制
            recordingTimer?.invalidate()
            recordingTimer = nil
            isPaused = true
            streamOutput?.setPaused(true)
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
        streamOutput?.setPaused(false)
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
            UserDefaults.standard.set(30, forKey: "scrollingCaptureSlices")
            UserDefaults.standard.set(0.8, forKey: "scrollingCaptureDelay")
            UserDefaults.standard.set(12, forKey: "scrollingCaptureLines")
            UserDefaults.standard.set("down", forKey: "scrollingCaptureDirection")
            UserDefaults.standard.set(true, forKey: "scrollingCaptureTrimOverlap")
            UserDefaults.standard.set(true, forKey: "scrollingCaptureDetectContentArea")
            UserDefaults.standard.set(true, forKey: "scrollingCaptureStopWhenUnchanged")
            UserDefaults.standard.set("#HEX", forKey: "colorCodeFormat")
            UserDefaults.standard.set(false, forKey: "screenshotRoundedCorners")
            UserDefaults.standard.set(false, forKey: "screenshotDropShadow")
            UserDefaults.standard.set(18.0, forKey: "screenshotCornerRadius")
            UserDefaults.standard.set(24.0, forKey: "screenshotShadowRadius")
            UserDefaults.standard.set("#000000", forKey: "screenshotShadowColorHex")
            UserDefaults.standard.set(42.0, forKey: "deviceFrameBezelWidth")
            UserDefaults.standard.set(48.0, forKey: "deviceFramePadding")
            UserDefaults.standard.set(26.0, forKey: "deviceFrameCornerRadius")
            UserDefaults.standard.set(28.0, forKey: "deviceFrameShadowRadius")
            UserDefaults.standard.set("#141414", forKey: "deviceFrameBodyColorHex")
            UserDefaults.standard.set("#000000", forKey: "deviceFrameShadowColorHex")
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

    @MainActor
    private func showRecordingCompletionNotification(diagnostics: RecordingAudioDiagnostics, duration: TimeInterval, audioOnly: Bool) {
        if diagnostics.hasAudioIssue {
            let missingAudioMessage: String
            if diagnostics.audioTrackCount == 0 {
                missingAudioMessage = "未检测到音频轨道"
            } else {
                missingAudioMessage = diagnostics.summaryText
            }
            NotificationManager.shared.showErrorNotification(
                title: audioOnly ? "录音完成，音频需检查" : "录制完成，音频需检查",
                message: "\(diagnostics.outputURL.lastPathComponent)：\(missingAudioMessage)"
            )
        } else {
            NotificationManager.shared.showRecordingCompleteNotification(
                filePath: diagnostics.outputURL,
                duration: duration,
                audioDiagnostics: diagnostics,
                audioOnly: audioOnly
            )
        }
    }

    @MainActor
    private func confirmRecordingPreflight(audioOnly: Bool) -> Bool {
        let settingsView = RecordingPreflightSettingsView(audioOnly: audioOnly)
        let alert = NSAlert()
        alert.messageText = audioOnly ? "开始录音前确认" : "开始录屏前确认"
        alert.informativeText = audioOnly
            ? "确认系统音频、麦克风和开录延时。"
            : "确认清晰度、帧数、开录延时、系统音频、麦克风和导出格式。"
        alert.alertStyle = .informational
        alert.accessoryView = settingsView
        alert.addButton(withTitle: audioOnly ? "开始录音" : "开始录制")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }

        settingsView.save()
        return true
    }

    @MainActor
    private func waitForRecordingStartDelayIfNeeded(subtitle: String) async throws {
        let startDelay = UserDefaults.standard.integer(forKey: "recordingStartDelaySeconds")
        guard startDelay > 0 else { return }

        let countdownOverlay = ScreenshotCountdownOverlayController(subtitle: subtitle)

        defer {
            countdownOverlay.close()
        }

        for remaining in stride(from: startDelay, through: 1, by: -1) {
            countdownOverlay.show(remaining: remaining)
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        countdownOverlay.close()
        try await Task.sleep(nanoseconds: 160_000_000)
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
    private func captureRegionScreenshot(autoOpenAfterCapture: Bool = true, forceSave: Bool = false) async throws -> NSImage {
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
                            do {
                                let finalImage = try await self.finalizeCapturedImage(
                                    image,
                                    showEditor: true,
                                    autoOpenAfterCapture: autoOpenAfterCapture,
                                    forceSave: forceSave
                                )
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

        return try await finalizeCapturedImage(nsImage, showEditor: false)
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

        return try await finalizeCapturedImage(nsImage, showEditor: false)
    }

    /// 捕获当前显示器画面但不保存，供长截图、带壳截图等高级功能复用。
    private func captureDisplayImageWithoutSaving(display requestedDisplay: SCDisplay? = nil, excludingWindows: [SCWindow] = []) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = requestedDisplay ?? selectedDisplay ?? content.displays.first else {
            throw CaptureError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: excludingWindows)
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

    private func captureWindowImage(_ window: SCWindow) async throws -> NSImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width))
        configuration.height = max(1, Int(window.frame.height))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        return NSImage(cgImage: cgImage, size: window.frame.size)
    }

    @MainActor
    private func preferredDisplay(from displays: [SCDisplay]) -> SCDisplay? {
        if let selectedDisplay {
            return selectedDisplay
        }

        guard let mouseLocation = CGEvent(source: nil)?.location else {
            return displays.first
        }

        return displays.first { display in
            CGDisplayBounds(display.displayID).contains(mouseLocation) || display.frame.contains(mouseLocation)
        } ?? displays.first
    }

    private func allDisplayBounds(from displays: [SCDisplay]) -> CGRect {
        let displayRects = displays
            .map { CGDisplayBounds($0.displayID) }
            .filter { !$0.isNull && !$0.isEmpty }

        guard var bounds = displayRects.first else {
            return .null
        }

        for rect in displayRects.dropFirst() {
            bounds = bounds.union(rect)
        }

        return bounds.integral
    }

    @MainActor
    private func selectMultipleWindows(
        from windows: [SCWindow],
        displayBounds: CGRect,
        singleClickCompletes: Bool = false
    ) async throws -> MultiWindowSelectionResult {
        let selectionFrame = selectionOverlayFrame(for: displayBounds)
        guard !selectionFrame.isNull && !selectionFrame.isEmpty else {
            throw CaptureError.noDisplayAvailable
        }

        let candidates = windows.map { window in
            MultiWindowSelectionCandidate(
                id: window.windowID,
                title: window.title ?? window.owningApplication?.applicationName ?? "窗口",
                window: window,
                screenRect: window.frame.intersection(selectionFrame)
            )
        }
        .filter { $0.screenRect.width > 40 && $0.screenRect.height > 40 }

        guard !candidates.isEmpty else {
            throw CaptureError.noWindowSelected
        }

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let selectionWindow = NSWindow(
                contentRect: selectionFrame,
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

            let overlayView = MultiWindowSelectionView(
                screenFrame: selectionFrame,
                candidates: candidates,
                singleClickCompletes: singleClickCompletes
            ) { result in
                guard !didResume else { return }
                didResume = true
                selectionWindow.contentView = nil
                selectionWindow.close()
                continuation.resume(with: result)
            }

            selectionWindow.contentView = overlayView
            selectionWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func selectionOverlayFrame(for displayBounds: CGRect) -> CGRect {
        let matchingScreens = NSScreen.screens
            .map(\.frame)
            .filter { $0.intersects(displayBounds) }

        guard var frame = matchingScreens.first else {
            return displayBounds
        }

        for screenFrame in matchingScreens.dropFirst() {
            frame = frame.union(screenFrame)
        }

        return frame.integral
    }

    private func renderMultiWindowComposite(
        _ windows: [SCWindow],
        displays: [SCDisplay],
        allWindows: [SCWindow],
        useDesktopBackdrop: Bool
    ) async throws -> NSImage {
        guard !windows.isEmpty else {
            throw CaptureError.noWindowSelected
        }

        let displayBounds = allDisplayBounds(from: displays)
        guard !displayBounds.isNull else {
            throw CaptureError.noDisplayAvailable
        }

        let windowFrames = windows.map(\.frame).filter { $0.width > 1 && $0.height > 1 }
        guard var outputRect = windowFrames.first else {
            throw CaptureError.failedToCapture
        }

        for frame in windowFrames.dropFirst() {
            outputRect = outputRect.union(frame)
        }
        outputRect = outputRect.insetBy(dx: -24, dy: -24).intersection(displayBounds).integral

        let backdropSegments = useDesktopBackdrop
            ? try await captureDesktopBackdropSegments(
                displays: displays,
                outputRect: outputRect,
                allWindows: allWindows
            )
            : []

        var capturedWindows: [(window: SCWindow, image: NSImage)] = []
        for window in windows {
            capturedWindows.append((window: window, image: try await captureWindowImage(window)))
        }

        let output = NSImage(size: outputRect.size)
        output.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: outputRect.size).fill()

        for (visibleRect, backdrop) in backdropSegments {
            let drawRect = NSRect(
                x: visibleRect.minX - outputRect.minX,
                y: outputRect.height - (visibleRect.maxY - outputRect.minY),
                width: visibleRect.width,
                height: visibleRect.height
            )
            backdrop.draw(in: drawRect)
        }

        for (window, image) in capturedWindows {
            let frame = window.frame.intersection(outputRect)
            guard frame.width > 1, frame.height > 1 else { continue }
            let drawRect = NSRect(
                x: frame.minX - outputRect.minX,
                y: outputRect.height - (frame.maxY - outputRect.minY),
                width: frame.width,
                height: frame.height
            )
            image.draw(in: drawRect)
        }

        output.unlockFocus()
        return output
    }

    private func captureDesktopBackdropSegments(
        displays: [SCDisplay],
        outputRect: CGRect,
        allWindows: [SCWindow]
    ) async throws -> [(visibleRect: CGRect, image: NSImage)] {
        var segments: [(visibleRect: CGRect, image: NSImage)] = []

        for display in displays {
            let displayBounds = CGDisplayBounds(display.displayID)
            let visibleRect = outputRect.intersection(displayBounds)
            guard visibleRect.width > 1, visibleRect.height > 1 else { continue }

            let desktopImage = try await captureDisplayImageWithoutSaving(
                display: display,
                excludingWindows: allWindows
            )
            let croppedBackdrop = cropDisplayImage(desktopImage, to: visibleRect, in: display)
            segments.append((visibleRect, croppedBackdrop))
        }

        return segments
    }

    private func scrollingCaptureTargetUnderMouse(from content: SCShareableContent) -> ScrollingCaptureTarget? {
        guard let mouseLocation = CGEvent(source: nil)?.location,
              let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let currentPID = Int(ProcessInfo.processInfo.processIdentifier)
        for windowInfo in windowList {
            let layer = windowInfo[kCGWindowLayer as String] as? Int ?? Int.max
            guard layer == 0 else { continue }

            let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int ?? 0
            guard ownerPID != currentPID else { continue }

            let alpha = windowInfo[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0 else { continue }

            guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let windowBounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  windowBounds.width > 120,
                  windowBounds.height > 120,
                  windowBounds.contains(mouseLocation) else {
                continue
            }

            guard let display = content.displays.first(where: { display in
                CGDisplayBounds(display.displayID).intersects(windowBounds)
            }) else {
                continue
            }

            let displayBounds = CGDisplayBounds(display.displayID)
            let windowCropRect = windowBounds.intersection(displayBounds)
            guard windowCropRect.width > 80, windowCropRect.height > 80 else { continue }

            if let contentCropRect = scrollingContentAreaUnderMouse(
                ownerPID: ownerPID,
                mouseLocation: mouseLocation,
                windowBounds: windowBounds,
                displayBounds: displayBounds
            ) {
                return ScrollingCaptureTarget(
                    display: display,
                    cropRect: contentCropRect,
                    source: .accessibilityContentArea
                )
            }

            return ScrollingCaptureTarget(
                display: display,
                cropRect: windowCropRect,
                source: .window
            )
        }

        return nil
    }

    private func scrollingContentAreaUnderMouse(
        ownerPID: Int,
        mouseLocation: CGPoint,
        windowBounds: CGRect,
        displayBounds: CGRect
    ) -> CGRect? {
        guard UserDefaults.standard.object(forKey: "scrollingCaptureDetectContentArea") as? Bool ?? true,
              AXIsProcessTrusted() else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(pid_t(ownerPID))
        var element: AXUIElement?
        let hitTestResult = AXUIElementCopyElementAtPosition(
            appElement,
            Float(mouseLocation.x),
            Float(mouseLocation.y),
            &element
        )

        guard hitTestResult == .success, let element else {
            return nil
        }

        let candidates = accessibilityAncestors(startingAt: element, limit: 14)
        let rolePriority = [
            kAXScrollAreaRole as String: 0,
            "AXWebArea": 1,
            kAXTableRole as String: 2,
            kAXOutlineRole as String: 2,
            kAXListRole as String: 3,
            kAXTextAreaRole as String: 4
        ]

        let rankedFrames: [(priority: Int, area: CGFloat, frame: CGRect)] = candidates.compactMap { candidate in
            guard let role = accessibilityStringAttribute(kAXRoleAttribute, from: candidate),
                  let priority = rolePriority[role],
                  let frame = accessibilityFrame(of: candidate) else {
                return nil
            }

            let clippedFrame = frame
                .intersection(windowBounds)
                .intersection(displayBounds)

            guard clippedFrame.width >= 160,
                  clippedFrame.height >= 120,
                  clippedFrame.contains(mouseLocation) else {
                return nil
            }

            return (priority, clippedFrame.width * clippedFrame.height, clippedFrame)
        }

        return rankedFrames
            .sorted { left, right in
                if left.priority != right.priority {
                    return left.priority < right.priority
                }
                return left.area < right.area
            }
            .first?
            .frame
    }

    private func accessibilityAncestors(startingAt element: AXUIElement, limit: Int) -> [AXUIElement] {
        var elements: [AXUIElement] = []
        var current: AXUIElement? = element

        for _ in 0..<limit {
            guard let element = current else { break }
            elements.append(element)
            current = accessibilityElementAttribute(kAXParentAttribute, from: element)
        }

        return elements
    }

    private func accessibilityFrame(of element: AXUIElement) -> CGRect? {
        guard let position = accessibilityCGPointAttribute(kAXPositionAttribute, from: element),
              let size = accessibilityCGSizeAttribute(kAXSizeAttribute, from: element) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func accessibilityElementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func accessibilityStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? String
    }

    private func accessibilityCGPointAttribute(_ attribute: String, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard
              AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func accessibilityCGSizeAttribute(_ attribute: String, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard
              AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private func cropDisplayImage(_ image: NSImage, to quartzRect: CGRect, in display: SCDisplay) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        let displayBounds = CGDisplayBounds(display.displayID)
        guard displayBounds.width > 0, displayBounds.height > 0 else {
            return image
        }

        let scaleX = CGFloat(cgImage.width) / displayBounds.width
        let scaleY = CGFloat(cgImage.height) / displayBounds.height
        let cropRect = CGRect(
            x: (quartzRect.minX - displayBounds.minX) * scaleX,
            y: (quartzRect.minY - displayBounds.minY) * scaleY,
            width: quartzRect.width * scaleX,
            height: quartzRect.height * scaleY
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        guard cropRect.width > 1,
              cropRect.height > 1,
              let croppedImage = cgImage.cropping(to: cropRect) else {
            return image
        }

        return NSImage(
            cgImage: croppedImage,
            size: NSSize(width: croppedImage.width, height: croppedImage.height)
        )
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
    private func captureInteractiveScreenshot(arguments: [String], forceStyle: Bool = true, showEditor: Bool, autoOpenAfterCapture: Bool = true) async throws -> NSImage {
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
                            let finalImage = try await self.finalizeCapturedImage(image, forceStyle: forceStyle, showEditor: showEditor, autoOpenAfterCapture: autoOpenAfterCapture)
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
    private func finalizeCapturedImage(
        _ image: NSImage,
        forceStyle: Bool = true,
        showEditor: Bool,
        autoOpenAfterCapture: Bool = true,
        forceSave: Bool = false
    ) async throws -> NSImage {
        let finalImage = forceStyle ? applyOutputStyle(to: image) : image
        let shouldAutoOpen = autoOpenAfterCapture &&
            (UserDefaults.standard.object(forKey: "autoOpenAfterCaptureInConfiguredApp") as? Bool ?? false)
        let shouldSave = forceSave || UserDefaults.standard.bool(forKey: "autoSaveScreenshots") || shouldAutoOpen

        if shouldSave {
            try await saveScreenshot(finalImage)
        }

        await MainActor.run {
            lastCapturedImage = finalImage
            if !shouldSave {
                lastSavedImageURL = nil
            }

            if showEditor {
                WindowManager.shared.showEditingWindow(for: finalImage)
            }

            if shouldAutoOpen {
                do {
                    try openLastScreenshotInConfiguredApp()
                } catch {
                    print("自动打开截图失败: \(error)")
                }
            }
        }

        return finalImage
    }

    private func applyOutputStyle(to image: NSImage) -> NSImage {
        var currentImage = image
        var appliedCornerRadius: CGFloat?

        if UserDefaults.standard.bool(forKey: "screenshotRoundedCorners") {
            let radius = CGFloat(UserDefaults.standard.double(forKey: "screenshotCornerRadius"))
            currentImage = renderRoundedImage(currentImage, radius: radius)
            appliedCornerRadius = radius
        }

        if UserDefaults.standard.bool(forKey: "screenshotDropShadow") {
            let radius = CGFloat(UserDefaults.standard.double(forKey: "screenshotShadowRadius"))
            let shadowColor = colorFromHex(UserDefaults.standard.string(forKey: "screenshotShadowColorHex") ?? "#000000") ?? .black
            currentImage = renderShadowedImage(
                currentImage,
                shadowRadius: radius,
                shadowColor: shadowColor,
                cornerRadius: appliedCornerRadius
            )
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

    private func renderShadowedImage(_ image: NSImage, shadowRadius: CGFloat, shadowColor: NSColor, cornerRadius: CGFloat? = nil) -> NSImage {
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
        let backgroundPath: NSBezierPath
        if let cornerRadius, cornerRadius > 0 {
            backgroundPath = NSBezierPath(
                roundedRect: imageRect,
                xRadius: cornerRadius,
                yRadius: cornerRadius
            )
        } else {
            backgroundPath = NSBezierPath(rect: imageRect)
        }

        NSColor.white.setFill()
        backgroundPath.fill()
        image.draw(in: imageRect)

        output.unlockFocus()
        return output
    }

    private func renderDeviceFrame(around image: NSImage) -> NSImage {
        let bezel = clampedCGFloat(UserDefaults.standard.double(forKey: "deviceFrameBezelWidth"), min: 18, max: 96, fallback: 42)
        let titleBar = max(24, bezel * 0.8)
        let padding = clampedCGFloat(UserDefaults.standard.double(forKey: "deviceFramePadding"), min: 16, max: 120, fallback: 48)
        let cornerRadius = clampedCGFloat(UserDefaults.standard.double(forKey: "deviceFrameCornerRadius"), min: 8, max: 64, fallback: 26)
        let shadowRadius = clampedCGFloat(UserDefaults.standard.double(forKey: "deviceFrameShadowRadius"), min: 0, max: 80, fallback: 28)
        let bodyColor = colorFromHex(UserDefaults.standard.string(forKey: "deviceFrameBodyColorHex") ?? "#141414") ?? NSColor(calibratedWhite: 0.08, alpha: 1)
        let shadowColor = colorFromHex(UserDefaults.standard.string(forKey: "deviceFrameShadowColorHex") ?? "#000000") ?? .black
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
        shadow.shadowBlurRadius = shadowRadius
        shadow.shadowOffset = NSSize(width: 0, height: -max(4, shadowRadius / 3))
        shadow.shadowColor = shadowColor.withAlphaComponent(shadowRadius > 0 ? 0.32 : 0)
        shadow.set()

        bodyColor.setFill()
        NSBezierPath(roundedRect: bodyRect, xRadius: cornerRadius, yRadius: cornerRadius).fill()

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

    private func clampedCGFloat(_ value: Double, min minimum: CGFloat, max maximum: CGFloat, fallback: CGFloat) -> CGFloat {
        guard value.isFinite else { return fallback }
        return Swift.min(Swift.max(CGFloat(value), minimum), maximum)
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

    private func imagesAreVisuallySimilar(_ previous: NSImage, _ next: NSImage) -> Bool {
        guard let previousCG = previous.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let nextCG = next.cgImage(forProposedRect: nil, context: nil, hints: nil),
              previousCG.width == nextCG.width,
              previousCG.height == nextCG.height,
              let previousBuffer = rgbaBuffer(from: previousCG),
              let nextBuffer = rgbaBuffer(from: nextCG) else {
            return false
        }

        let width = previousCG.width
        let height = previousCG.height
        let sampleXStride = max(8, width / 96)
        let sampleYStride = max(8, height / 96)
        var totalDifference = 0
        var samples = 0
        var changedSamples = 0

        for y in stride(from: 0, to: height, by: sampleYStride) {
            for x in stride(from: 0, to: width, by: sampleXStride) {
                let offset = (y * width + x) * 4
                let difference =
                    abs(Int(previousBuffer[offset]) - Int(nextBuffer[offset])) +
                    abs(Int(previousBuffer[offset + 1]) - Int(nextBuffer[offset + 1])) +
                    abs(Int(previousBuffer[offset + 2]) - Int(nextBuffer[offset + 2]))

                totalDifference += difference
                samples += 3
                if difference > 18 {
                    changedSamples += 1
                }
            }
        }

        guard samples > 0 else { return false }
        let averageDifference = Double(totalDifference) / Double(samples)
        let changedRatio = Double(changedSamples) / Double(max(1, samples / 3))
        return averageDifference < 1.8 && changedRatio < 0.015
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

    private func scrollActiveView(lines: Int, direction: String) {
        let wheelDelta = direction == "up" ? Int32(lines) : -Int32(lines)
        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: wheelDelta,
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
                let text = self.readingOrderedTextObservations(observations)
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

    private func readingOrderedTextObservations(_ observations: [VNRecognizedTextObservation]) -> [VNRecognizedTextObservation] {
        observations.sorted { lhs, rhs in
            let lhsBox = lhs.boundingBox
            let rhsBox = rhs.boundingBox
            let lineTolerance = max(lhsBox.height, rhsBox.height) * 0.5
            let verticalDelta = lhsBox.midY - rhsBox.midY

            if abs(verticalDelta) > lineTolerance {
                return lhsBox.midY > rhsBox.midY
            }

            return lhsBox.minX < rhsBox.minX
        }
    }

    private func translateText(_ text: String, targetLanguage: String) async throws -> TranslationProviderResult {
        do {
            let translated = try await translateWithAppleInstalledModel(text, targetLanguage: targetLanguage)
            return TranslationProviderResult(text: translated, providerName: "Apple 本地翻译")
        } catch {
            // Fall through to online providers when the system model is unavailable or not installed.
        }

        do {
            let translated = try await translateWithGoogle(text, targetLanguage: targetLanguage)
            return TranslationProviderResult(text: translated, providerName: "Google")
        } catch {
            let translated = try await translateWithMyMemory(text, targetLanguage: targetLanguage)
            return TranslationProviderResult(text: translated, providerName: "MyMemory")
        }
    }

    func prepareAppleTranslationModels(targetLanguage: String) async -> String {
        guard #available(macOS 26.0, *) else {
            return "Apple 本地翻译模型准备需要 macOS 26 或更高版本；当前系统会继续使用在线翻译和网页兜底。"
        }

        let target = Locale.Language(identifier: appleLanguageCode(for: targetLanguage))
        let sourceCodes = ["en", "zh-Hans", "ja", "ko"].filter { sourceCode in
            let source = Locale.Language(identifier: sourceCode)
            return source.languageCode != target.languageCode ||
                source.script != target.script ||
                source.region != target.region
        }

        let availability = LanguageAvailability()
        var installedPairs: [String] = []
        var preparedPairs: [String] = []
        var pendingPairs: [String] = []
        var unsupportedPairs: [String] = []

        for sourceCode in sourceCodes {
            let source = Locale.Language(identifier: sourceCode)
            let label = "\(displayName(forAppleLanguageCode: sourceCode)) -> \(displayName(forAppleLanguageCode: targetLanguage))"
            let status = await availability.status(from: source, to: target)

            switch status {
            case .installed:
                installedPairs.append(label)
            case .supported:
                let session = TranslationSession(installedSource: source, target: target)
                guard session.canRequestDownloads else {
                    pendingPairs.append("\(label)（系统暂不允许自动下载）")
                    continue
                }

                do {
                    try await session.prepareTranslation()
                    let refreshedStatus = await availability.status(from: source, to: target)
                    if refreshedStatus == .installed {
                        preparedPairs.append(label)
                    } else {
                        pendingPairs.append("\(label)（已请求准备，系统仍显示未安装）")
                    }
                } catch {
                    pendingPairs.append("\(label)（准备失败：\(error.localizedDescription)）")
                }
            case .unsupported:
                unsupportedPairs.append(label)
            @unknown default:
                pendingPairs.append("\(label)（系统返回未知状态）")
            }
        }

        var lines: [String] = []
        if !installedPairs.isEmpty {
            lines.append("已安装：\(installedPairs.joined(separator: "，"))")
        }
        if !preparedPairs.isEmpty {
            lines.append("已准备：\(preparedPairs.joined(separator: "，"))")
        }
        if !pendingPairs.isEmpty {
            lines.append("需手动处理：\(pendingPairs.joined(separator: "，"))")
        }
        if !unsupportedPairs.isEmpty {
            lines.append("系统不支持：\(unsupportedPairs.joined(separator: "，"))")
        }

        return lines.isEmpty ? "没有需要准备的本地翻译模型。" : lines.joined(separator: "\n")
    }

    private func translateWithAppleInstalledModel(_ text: String, targetLanguage: String) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw CaptureError.failedToTranslate
        }

        let sourceLanguage = Locale.Language(identifier: appleLanguageCode(for: detectedTranslationLanguage(for: text)))
        let target = Locale.Language(identifier: appleLanguageCode(for: targetLanguage))

        if sourceLanguage.languageCode == target.languageCode,
           sourceLanguage.script == target.script,
           sourceLanguage.region == target.region {
            return text
        }

        let availability = LanguageAvailability()
        let status = await availability.status(from: sourceLanguage, to: target)
        guard status == .installed else {
            throw CaptureError.failedToTranslate
        }

        let session = TranslationSession(installedSource: sourceLanguage, target: target)
        try await session.prepareTranslation()
        let response = try await session.translate(text)
        let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translated.isEmpty else {
            throw CaptureError.failedToTranslate
        }

        return translated
    }

    private func translateWithGoogle(_ text: String, targetLanguage: String) async throws -> String {
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

    private func translateWithMyMemory(_ text: String, targetLanguage: String) async throws -> String {
        let sourceLanguage = detectedTranslationLanguage(for: text)
        let mappedTargetLanguage = myMemoryLanguageCode(for: targetLanguage)
        let chunks = text.utf8Chunks(maxByteCount: 480)
        guard !chunks.isEmpty else {
            throw CaptureError.failedToTranslate
        }

        var translatedChunks: [String] = []
        for chunk in chunks {
            translatedChunks.append(try await translateMyMemoryChunk(
                chunk,
                sourceLanguage: sourceLanguage,
                targetLanguage: mappedTargetLanguage
            ))
        }

        let translated = translatedChunks
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !translated.isEmpty else {
            throw CaptureError.failedToTranslate
        }

        return translated
    }

    private func translateMyMemoryChunk(_ text: String, sourceLanguage: String, targetLanguage: String) async throws -> String {
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")
        components?.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "\(sourceLanguage)|\(targetLanguage)")
        ]

        guard let url = components?.url else {
            throw CaptureError.failedToTranslate
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw CaptureError.failedToTranslate
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseData = root["responseData"] as? [String: Any],
              let translatedText = responseData["translatedText"] as? String else {
            throw CaptureError.failedToTranslate
        }

        let trimmed = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CaptureError.failedToTranslate
        }

        return trimmed
    }

    private func detectedTranslationLanguage(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else {
            return "en"
        }

        switch language {
        case .simplifiedChinese:
            return "zh-CN"
        case .traditionalChinese:
            return "zh-TW"
        case .english:
            return "en"
        case .japanese:
            return "ja"
        case .korean:
            return "ko"
        default:
            return language.rawValue
        }
    }

    private func myMemoryLanguageCode(for targetLanguage: String) -> String {
        switch targetLanguage {
        case "zh-CN":
            return "zh-CN"
        case "zh-TW":
            return "zh-TW"
        default:
            return targetLanguage
        }
    }

    private func appleLanguageCode(for language: String) -> String {
        switch language {
        case "zh-CN":
            return "zh-Hans"
        case "zh-TW":
            return "zh-Hant"
        default:
            return language
        }
    }

    private func displayName(forAppleLanguageCode language: String) -> String {
        switch appleLanguageCode(for: language) {
        case "zh-Hans":
            return "简体中文"
        case "zh-Hant":
            return "繁体中文"
        case "en":
            return "English"
        case "ja":
            return "日本語"
        case "ko":
            return "한국어"
        default:
            return language
        }
    }

    @MainActor
    private func openWebTranslation(for text: String, targetLanguage: String) throws {
        guard let url = webTranslationURL(for: text, targetLanguage: targetLanguage) else {
            throw CaptureError.failedToTranslate
        }

        NSWorkspace.shared.open(url)
    }

    private func webTranslationURL(for text: String, targetLanguage: String) -> URL? {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        return URL(string: "https://translate.google.com/?sl=auto&tl=\(targetLanguage)&text=\(encoded)&op=translate")
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
    case recordingFailed(String)
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
        case .recordingFailed(let message):
            return message
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
    let providerName: String
    let usedWebFallback: Bool
}

private struct TranslationProviderResult {
    let text: String
    let providerName: String
}

@available(macOS 12.3, *)
@MainActor
private final class RecordingPreflightSettingsView: NSView {
    private let audioOnly: Bool
    private let frameRatePopup = NSPopUpButton()
    private let qualityPopup = NSPopUpButton()
    private let formatPopup = NSPopUpButton()
    private let delayStepper = NSStepper()
    private let delayLabel = NSTextField(labelWithString: "")
    private let systemAudioCheckbox = NSButton(checkboxWithTitle: "录制系统音频", target: nil, action: nil)
    private let microphoneCheckbox = NSButton(checkboxWithTitle: "录制麦克风", target: nil, action: nil)
    private let cursorCheckbox = NSButton(checkboxWithTitle: "显示鼠标指针", target: nil, action: nil)

    init(audioOnly: Bool) {
        self.audioOnly = audioOnly
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: audioOnly ? 150 : 272))
        setupControls()
        loadDefaults()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func save() {
        if !audioOnly {
            UserDefaults.standard.set(selectedFrameRate(), forKey: "recordingFrameRate")
            UserDefaults.standard.set(qualityPopup.titleOfSelectedItem ?? "高", forKey: "recordingQuality")
            UserDefaults.standard.set(formatPopup.titleOfSelectedItem ?? "MOV", forKey: "recordingFileFormat")
            UserDefaults.standard.set(cursorCheckbox.state == .on, forKey: "showCursor")
        }

        UserDefaults.standard.set(Int(delayStepper.integerValue), forKey: "recordingStartDelaySeconds")
        UserDefaults.standard.set(systemAudioCheckbox.state == .on, forKey: "includeSystemAudio")
        UserDefaults.standard.set(microphoneCheckbox.state == .on, forKey: "includeMicrophone")
    }

    private func setupControls() {
        frameRatePopup.addItems(withTitles: ["15 FPS", "30 FPS", "60 FPS"])
        qualityPopup.addItems(withTitles: ["低", "中", "高", "超高"])
        formatPopup.addItems(withTitles: ["MOV", "MP4"])

        delayStepper.minValue = 0
        delayStepper.maxValue = 30
        delayStepper.increment = 1
        delayStepper.target = self
        delayStepper.action = #selector(updateDelayLabel)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        if !audioOnly {
            stack.addArrangedSubview(row(title: "帧数", control: frameRatePopup))
            stack.addArrangedSubview(row(title: "清晰度", control: qualityPopup))
            stack.addArrangedSubview(row(title: "导出格式", control: formatPopup))
        }

        let delayStack = NSStackView()
        delayStack.orientation = .horizontal
        delayStack.spacing = 8
        delayStack.alignment = .centerY
        delayStack.addArrangedSubview(delayLabel)
        delayStack.addArrangedSubview(delayStepper)
        stack.addArrangedSubview(row(title: "开录延时", control: delayStack))

        stack.addArrangedSubview(systemAudioCheckbox)
        stack.addArrangedSubview(microphoneCheckbox)

        if !audioOnly {
            stack.addArrangedSubview(cursorCheckbox)
        }

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    private func loadDefaults() {
        let storedFrameRate = UserDefaults.standard.double(forKey: "recordingFrameRate")
        let frameRate = storedFrameRate == 0 ? 60 : Int(storedFrameRate)
        frameRatePopup.selectItem(withTitle: "\(frameRate) FPS")

        qualityPopup.selectItem(withTitle: UserDefaults.standard.string(forKey: "recordingQuality") ?? "高")
        formatPopup.selectItem(withTitle: UserDefaults.standard.string(forKey: "recordingFileFormat") ?? "MOV")

        delayStepper.integerValue = UserDefaults.standard.integer(forKey: "recordingStartDelaySeconds")
        updateDelayLabel()

        systemAudioCheckbox.state = UserDefaults.standard.bool(forKey: "includeSystemAudio") ? .on : .off
        microphoneCheckbox.state = UserDefaults.standard.bool(forKey: "includeMicrophone") ? .on : .off
        cursorCheckbox.state = UserDefaults.standard.bool(forKey: "showCursor") ? .on : .off
    }

    private func row(title: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 76).isActive = true

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        row.addArrangedSubview(label)
        row.addArrangedSubview(control)
        return row
    }

    private func selectedFrameRate() -> Double {
        let title = frameRatePopup.titleOfSelectedItem ?? "60 FPS"
        return Double(title.split(separator: " ").first ?? "60") ?? 60
    }

    @objc private func updateDelayLabel() {
        delayLabel.stringValue = "\(delayStepper.integerValue) 秒"
    }
}

private extension String {
    func utf8Chunks(maxByteCount: Int) -> [String] {
        guard maxByteCount > 0 else { return [] }

        var chunks: [String] = []
        var current = ""
        var currentByteCount = 0

        for character in self {
            let fragment = String(character)
            let fragmentByteCount = fragment.utf8.count

            if currentByteCount + fragmentByteCount > maxByteCount, !current.isEmpty {
                chunks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
                currentByteCount = 0
            }

            current.append(character)
            currentByteCount += fragmentByteCount

            if character.isNewline || character.isWhitespace,
               currentByteCount >= maxByteCount * 3 / 4 {
                chunks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
                currentByteCount = 0
            }
        }

        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            chunks.append(tail)
        }

        return chunks.filter { !$0.isEmpty }
    }
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

        let targetText = result.usedWebFallback ? "目标语言：\(result.targetLanguage) · 已打开网页翻译兜底" : "目标语言：\(result.targetLanguage) · \(result.providerName)"
        let targetLabel = NSTextField(labelWithString: targetText)
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
        guard !result.usedWebFallback else {
            copyToPasteboard(result.sourceText)
            return
        }
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

// MARK: - Multi Window Selection

@available(macOS 12.3, *)
private struct MultiWindowSelectionCandidate {
    let id: CGWindowID
    let title: String
    let window: SCWindow
    let screenRect: CGRect
}

@available(macOS 12.3, *)
private struct MultiWindowSelectionResult {
    let windows: [SCWindow]
    let usesDesktopBackdrop: Bool
}

@available(macOS 12.3, *)
final class MultiWindowSelectionView: NSView {
    private let screenFrame: CGRect
    private let candidates: [MultiWindowSelectionCandidate]
    private let singleClickCompletes: Bool
    private let completion: (Result<MultiWindowSelectionResult, Error>) -> Void
    private var selectedIDs = Set<CGWindowID>()
    private var hoverID: CGWindowID?
    private var desktopBackdropSelected = false

    fileprivate init(
        screenFrame: CGRect,
        candidates: [MultiWindowSelectionCandidate],
        singleClickCompletes: Bool,
        completion: @escaping (Result<MultiWindowSelectionResult, Error>) -> Void
    ) {
        self.screenFrame = screenFrame
        self.candidates = candidates
        self.singleClickCompletes = singleClickCompletes
        self.completion = completion
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self
        ))
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

        NSColor.black.withAlphaComponent(0.30).setFill()
        bounds.fill()

        for candidate in candidates {
            let rect = viewRect(for: candidate.screenRect)
            let selected = selectedIDs.contains(candidate.id)
            let hovered = hoverID == candidate.id

            (selected ? NSColor.systemBlue.withAlphaComponent(0.24) : NSColor.black.withAlphaComponent(0.08)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()

            let border = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
            border.lineWidth = selected ? 3 : (hovered ? 2 : 1)
            (selected ? NSColor.systemBlue : (hovered ? NSColor.white : NSColor.white.withAlphaComponent(0.45))).setStroke()
            border.stroke()

            drawWindowLabel(candidate.title, index: selectionIndex(for: candidate.id), in: rect)
        }

        drawInstruction()
        if desktopBackdropSelected {
            drawDesktopBackdropBadge()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hoverID = candidate(at: point)?.id
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let candidate = candidate(at: point) else {
            desktopBackdropSelected.toggle()
            needsDisplay = true
            return
        }

        if singleClickCompletes && !event.modifierFlags.contains(.shift) {
            completion(.success(MultiWindowSelectionResult(windows: [candidate.window], usesDesktopBackdrop: desktopBackdropSelected)))
            return
        }

        if selectedIDs.contains(candidate.id) {
            selectedIDs.remove(candidate.id)
        } else {
            selectedIDs.insert(candidate.id)
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            let selected = candidates.filter { selectedIDs.contains($0.id) }.map(\.window)
            guard !selected.isEmpty else {
                NSSound.beep()
                return
            }
            completion(.success(MultiWindowSelectionResult(windows: selected, usesDesktopBackdrop: desktopBackdropSelected)))
        case 53:
            completion(.failure(CaptureError.regionSelectionCancelled))
        default:
            super.keyDown(with: event)
        }
    }

    private func candidate(at point: CGPoint) -> MultiWindowSelectionCandidate? {
        candidates.reversed().first { viewRect(for: $0.screenRect).contains(point) }
    }

    private func viewRect(for screenRect: CGRect) -> CGRect {
        CGRect(
            x: screenRect.minX - screenFrame.minX,
            y: screenFrame.height - (screenRect.maxY - screenFrame.minY),
            width: screenRect.width,
            height: screenRect.height
        )
    }

    private func selectionIndex(for id: CGWindowID) -> Int? {
        let selected = candidates.filter { selectedIDs.contains($0.id) }
        return selected.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    private func drawWindowLabel(_ title: String, index: Int?, in rect: CGRect) {
        let prefix = index.map { "\($0). " } ?? ""
        let text = "\(prefix)\(title)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let maxWidth = max(60, rect.width - 16)
        let size = text.size(withAttributes: attributes)
        let labelRect = NSRect(
            x: rect.minX + 8,
            y: rect.maxY - min(size.height + 12, rect.height),
            width: min(size.width + 12, maxWidth),
            height: size.height + 8
        )
        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()
        text.draw(
            with: labelRect.insetBy(dx: 6, dy: 4),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes
        )
    }

    private func drawInstruction() {
        let text = singleClickCompletes
            ? "点击窗口截图；按住 Shift 可连续选择多个窗口，点桌面用壁纸作底板，按 Enter 合成"
            : "点击选择多个窗口，点桌面用壁纸作底板，按 Enter 合成，按 Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let rect = NSRect(
            x: bounds.midX - size.width / 2 - 14,
            y: bounds.maxY - size.height - 36,
            width: size.width + 28,
            height: size.height + 14
        )
        NSColor.black.withAlphaComponent(0.58).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        text.draw(at: CGPoint(x: rect.minX + 14, y: rect.minY + 7), withAttributes: attributes)
    }

    private func drawDesktopBackdropBadge() {
        let text = "桌面壁纸底板已启用"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let rect = NSRect(
            x: bounds.midX - size.width / 2 - 12,
            y: 28,
            width: size.width + 24,
            height: size.height + 12
        )
        NSColor.systemBlue.withAlphaComponent(0.86).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        text.draw(at: CGPoint(x: rect.minX + 12, y: rect.minY + 6), withAttributes: attributes)
    }
}

// MARK: - Delayed Screenshot Countdown

@available(macOS 12.3, *)
@MainActor
private final class ScreenshotCountdownOverlayController {
    private var window: NSWindow?
    private let label = NSTextField(labelWithString: "")
    private let subtitle: String

    init(subtitle: String = "准备截图") {
        self.subtitle = subtitle
    }

    func show(remaining: Int) {
        if window == nil {
            createWindow()
        }

        label.stringValue = "\(remaining)"
        window?.orderFrontRegardless()
    }

    func close() {
        window?.orderOut(nil)
        window?.close()
        window = nil
    }

    private func createWindow() {
        let size = NSSize(width: 156, height: 112)
        let screen = screenUnderMouse() ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height - 42
        )

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let contentView = CountdownOverlayView(label: label, subtitle: subtitle)
        window.contentView = contentView
        self.window = window
    }

    private func screenUnderMouse() -> NSScreen? {
        guard let mouseLocation = CGEvent(source: nil)?.location else {
            return nil
        }

        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }
}

@available(macOS 12.3, *)
private final class CountdownOverlayView: NSView {
    private let label: NSTextField
    private let subtitle: NSTextField

    init(label: NSTextField, subtitle: String) {
        self.label = label
        self.subtitle = NSTextField(labelWithString: subtitle)
        super.init(frame: NSRect(x: 0, y: 0, width: 156, height: 112))
        wantsLayer = true
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18).fill()

        NSColor.white.withAlphaComponent(0.18).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 18, yRadius: 18)
        border.lineWidth = 1
        border.stroke()
    }

    private func setupViews() {
        label.alignment = .center
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 50, weight: .bold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false

        subtitle.alignment = .center
        subtitle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.82)
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        addSubview(subtitle)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.heightAnchor.constraint(equalToConstant: 58),

            subtitle.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            subtitle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])
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
    private let requestedSystemAudio: Bool
    private let requestedMicrophone: Bool
    private let frameRate: Int
    private let quality: String
    private let audioOnly: Bool
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
    private var isFinishing = false
    private var lastDiagnostics: RecordingAudioDiagnostics?
    private var finishCompletions: [(RecordingAudioDiagnostics) -> Void] = []
    private let pauseLock = NSLock()
    private var paused = false
    private var pendingPauseStartTime: CMTime?
    private var accumulatedPausedDuration = CMTime.zero

    init(
        outputURL: URL,
        fileType: AVFileType = .mov,
        includeSystemAudio: Bool,
        includeMicrophone: Bool,
        frameRate: Int,
        quality: String,
        audioOnly: Bool = false
    ) {
        self.outputURL = outputURL
        self.fileType = fileType
        self.requestedSystemAudio = includeSystemAudio
        self.requestedMicrophone = includeMicrophone
        self.frameRate = frameRate
        self.quality = quality
        self.audioOnly = audioOnly
        super.init()
    }

    func setPaused(_ paused: Bool) {
        pauseLock.lock()
        self.paused = paused
        if paused {
            pendingPauseStartTime = nil
        }
        pauseLock.unlock()
    }

    private func pauseAdjustedSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> (sampleBuffer: CMSampleBuffer, presentationTime: CMTime)? {
        let originalPresentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        pauseLock.lock()

        if paused {
            if pendingPauseStartTime == nil {
                pendingPauseStartTime = originalPresentationTime
            }
            pauseLock.unlock()
            return nil
        }

        if let pauseStart = pendingPauseStartTime {
            let pausedDuration = CMTimeSubtract(originalPresentationTime, pauseStart)
            if pausedDuration.isValid && pausedDuration.seconds > 0 {
                accumulatedPausedDuration = CMTimeAdd(accumulatedPausedDuration, pausedDuration)
            }
            pendingPauseStartTime = nil
        }

        let timingOffset = accumulatedPausedDuration
        pauseLock.unlock()

        guard timingOffset.isValid && timingOffset.seconds > 0 else {
            return (sampleBuffer, originalPresentationTime)
        }

        let adjustedPresentationTime = CMTimeSubtract(originalPresentationTime, timingOffset)
        let adjustedSampleBuffer = copySampleBuffer(sampleBuffer, subtracting: timingOffset) ?? sampleBuffer
        return (adjustedSampleBuffer, adjustedPresentationTime)
    }

    private func copySampleBuffer(_ sampleBuffer: CMSampleBuffer, subtracting offset: CMTime) -> CMSampleBuffer? {
        var timingEntryCount = 0
        let countStatus = CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &timingEntryCount
        )
        guard countStatus == noErr, timingEntryCount > 0 else {
            return nil
        }

        var timing = Array(
            repeating: CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: .invalid,
                decodeTimeStamp: .invalid
            ),
            count: timingEntryCount
        )

        let timingStatus = CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: timingEntryCount,
            arrayToFill: &timing,
            entriesNeededOut: nil
        )
        guard timingStatus == noErr else {
            return nil
        }

        for index in timing.indices {
            if timing[index].presentationTimeStamp.isValid {
                timing[index].presentationTimeStamp = CMTimeSubtract(timing[index].presentationTimeStamp, offset)
            }
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = CMTimeSubtract(timing[index].decodeTimeStamp, offset)
            }
        }

        var adjustedSampleBuffer: CMSampleBuffer?
        let copyStatus = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: timingEntryCount,
            sampleTimingArray: &timing,
            sampleBufferOut: &adjustedSampleBuffer
        )

        guard copyStatus == noErr else {
            return nil
        }

        return adjustedSampleBuffer
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

            if audioOnly {
                addAudioInputs()
                return
            }

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

            let averageBitRate = videoBitRate(width: adjustedWidth, height: adjustedHeight)
            let profileLevel = h264ProfileLevel(for: quality)
            logMicrophone("视频编码配置: quality=\(quality), frameRate=\(frameRate), bitRate=\(averageBitRate), profile=\(profileLevel)")

            // 视频输入设置 - 使用 QuickTime 兼容的 H.264 设置
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: adjustedWidth,
                AVVideoHeightKey: adjustedHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoProfileLevelKey: profileLevel,
                    AVVideoAverageBitRateKey: averageBitRate,
                    AVVideoMaxKeyFrameIntervalKey: frameRate,
                    AVVideoAllowFrameReorderingKey: false,
                    AVVideoExpectedSourceFrameRateKey: frameRate,
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

            addAudioInputs()

        } catch {
            print("设置资产写入器失败: \(error)")
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let adjustedSample = pauseAdjustedSampleBuffer(sampleBuffer) else {
            return
        }

        let sampleBuffer = adjustedSample.sampleBuffer
        let presentationTime = adjustedSample.presentationTime

        // 视频录制等待首个屏幕帧初始化；独立录音等待首个音频帧初始化。
        if assetWriter == nil && (type == .screen || (audioOnly && (type == .audio || type == .microphone))) {
            print(audioOnly ? "首次收到音频帧，设置资产写入器..." : "首次收到视频帧，设置资产写入器...")
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
            assetWriter.startSession(atSourceTime: presentationTime)
            isWritingStarted = true
            print("录制会话已开始，时间戳: \(presentationTime), 帧类型: \(type)")
            logMicrophone("✓ AVAssetWriter 会话已启动，起始时间: \(presentationTime)", level: "SUCCESS")
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

    func finishWriting(completion: ((RecordingAudioDiagnostics) -> Void)? = nil) {
        if let lastDiagnostics {
            completion?(lastDiagnostics)
            return
        }

        if let completion {
            finishCompletions.append(completion)
        }

        guard !isFinishing else { return }
        isFinishing = true

        guard let assetWriter = assetWriter else {
            print("资产写入器为空，无法完成写入")
            logMicrophone("资产写入器为空，无法完成写入", level: "ERROR")
            completeFinish(makeDiagnostics(assetWriterSucceeded: false, fileSize: 0, videoTrackCount: 0, audioTrackCount: 0))
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

                var fileSize: Int64 = 0
                var videoTrackCount = 0
                var audioTrackCount = 0
                var assetWriterSucceeded = false

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
                            fileSize = attributes[.size] as? Int64 ?? 0
                            print("录制文件大小: \(fileSize) 字节")
                            logMicrophone("录制文件大小: \(fileSize) 字节")

                            if fileSize > 0 {
                                print("录制文件有效")
                                assetWriterSucceeded = true

                                // 使用 AVAsset 检查音频轨道
                                let inspection = self.inspectVideoFile(url: finalOutputURL)
                                videoTrackCount = inspection.videoTrackCount
                                audioTrackCount = inspection.audioTrackCount
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

                self.completeFinish(self.makeDiagnostics(
                    assetWriterSucceeded: assetWriterSucceeded,
                    fileSize: fileSize,
                    videoTrackCount: videoTrackCount,
                    audioTrackCount: audioTrackCount
                ))
            }
        }
    }

    /// 检查视频文件的音频轨道
    private func inspectVideoFile(url: URL) -> (videoTrackCount: Int, audioTrackCount: Int) {
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
        return (videoTracks.count, audioTracks.count)
    }

    private func makeDiagnostics(assetWriterSucceeded: Bool, fileSize: Int64, videoTrackCount: Int, audioTrackCount: Int) -> RecordingAudioDiagnostics {
        RecordingAudioDiagnostics(
            outputURL: outputURL,
            requestedSystemAudio: requestedSystemAudio,
            requestedMicrophone: requestedMicrophone,
            videoFrameCount: frameCount,
            systemAudioFrameCount: audioFrameCount,
            microphoneFrameCount: micFrameCount,
            systemAudioFailCount: audioFailCount,
            microphoneFailCount: micFailCount,
            videoTrackCount: videoTrackCount,
            audioTrackCount: audioTrackCount,
            fileSize: fileSize,
            assetWriterSucceeded: assetWriterSucceeded
        )
    }

    private func addAudioInputs() {
        logMicrophone("AVAssetWriter 音频配置:")
        logMicrophone("  - includeSystemAudio: \(requestedSystemAudio)")
        logMicrophone("  - includeMicrophone: \(requestedMicrophone)")
        logMicrophone("  - audioOnly: \(audioOnly)")

        print("🎵 音频配置 - 系统音频: \(requestedSystemAudio), 麦克风: \(requestedMicrophone), 仅录音: \(audioOnly)")

        guard requestedSystemAudio || requestedMicrophone else {
            print("⚠️ 未启用任何音频录制")
            return
        }

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]

        if requestedSystemAudio {
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

        if requestedMicrophone {
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
        logMicrophone("  - 系统音频: \(requestedSystemAudio ? "启用" : "禁用")")
        logMicrophone("  - 麦克风: \(requestedMicrophone ? "启用" : "禁用")")
        logMicrophone("  - 编码格式: AAC 48kHz 立体声")
    }

    private func videoBitRate(width: Int, height: Int) -> Int {
        let pixelsPerSecond = Double(width * height * frameRate)
        let bitsPerPixel: Double

        switch quality {
        case "低":
            bitsPerPixel = 0.04
        case "中":
            bitsPerPixel = 0.07
        case "超高":
            bitsPerPixel = 0.16
        default:
            bitsPerPixel = 0.11
        }

        let calculatedBitRate = Int(pixelsPerSecond * bitsPerPixel)
        return min(max(calculatedBitRate, 2_000_000), 60_000_000)
    }

    private func h264ProfileLevel(for quality: String) -> String {
        switch quality {
        case "低":
            return AVVideoProfileLevelH264BaselineAutoLevel
        case "中":
            return AVVideoProfileLevelH264MainAutoLevel
        default:
            return AVVideoProfileLevelH264HighAutoLevel
        }
    }

    private func completeFinish(_ diagnostics: RecordingAudioDiagnostics) {
        lastDiagnostics = diagnostics
        let completions = finishCompletions
        finishCompletions.removeAll()

        logMicrophone("========== 录制音频验收 ==========")
        logMicrophone("请求系统音频: \(diagnostics.requestedSystemAudio)")
        logMicrophone("请求麦克风: \(diagnostics.requestedMicrophone)")
        logMicrophone("文件音频轨道数量: \(diagnostics.audioTrackCount)", level: diagnostics.hasAudioIssue ? "ERROR" : "SUCCESS")
        logMicrophone("音频摘要: \(diagnostics.summaryText)")

        completions.forEach { $0(diagnostics) }
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
