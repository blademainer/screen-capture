//
//  SettingsView.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var permissionManager: PermissionManager
    @AppStorage("autoSaveScreenshots") private var autoSaveScreenshots = true
    @AppStorage("screenshotFormat") private var screenshotFormat = "PNG"
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("hideMenuBarIcon") private var hideMenuBarIcon = false
    @AppStorage("defaultSaveLocation") private var defaultSaveLocation = ""
    @AppStorage("autoHideWindowDuringCapture") private var autoHideWindowDuringCapture = true
    @AppStorage("autoShowWindowAfterCapture") private var autoShowWindowAfterCapture = false
    @AppStorage("delayedScreenshotSeconds") private var delayedScreenshotSeconds = 5
    @AppStorage("scrollingCaptureSlices") private var scrollingCaptureSlices = 5
    @AppStorage("scrollingCaptureDelay") private var scrollingCaptureDelay = 0.8
    @AppStorage("scrollingCaptureLines") private var scrollingCaptureLines = 12
    @AppStorage("scrollingCaptureTrimOverlap") private var scrollingCaptureTrimOverlap = true
    @AppStorage("screenshotRoundedCorners") private var screenshotRoundedCorners = false
    @AppStorage("screenshotDropShadow") private var screenshotDropShadow = false
    @AppStorage("screenshotCornerRadius") private var screenshotCornerRadius = 18.0
    @AppStorage("screenshotShadowRadius") private var screenshotShadowRadius = 24.0
    @AppStorage("colorCodeFormat") private var colorCodeFormat = "#HEX"
    @AppStorage("openAfterCaptureAppPath") private var openAfterCaptureAppPath = ""
    @AppStorage("translationTargetLanguage") private var translationTargetLanguage = "zh-CN"
    @AppStorage("recordingFrameRate") private var recordingFrameRate = 60.0
    @AppStorage("recordingQuality") private var recordingQuality = "高"
    @AppStorage("includeSystemAudio") private var includeSystemAudio = true
    @AppStorage("includeMicrophone") private var includeMicrophone = true
    @AppStorage("showCursor") private var showCursor = true
    @AppStorage("recordingStartDelaySeconds") private var recordingStartDelaySeconds = 0
    @AppStorage("recordingFileFormat") private var recordingFileFormat = "MOV"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 权限状态
                PermissionStatusSection()

                Divider()

                // 截图设置
                ScreenshotSettingsSection()

                Divider()

                // 录制设置
                RecordingSettingsSection()

                Divider()

                // 窗口行为设置
                WindowBehaviorSettingsSection()

                Divider()

                // 浮窗设置
                FloatingWindowSettingsSection()

                Divider()

                // 通用设置
                GeneralSettingsSection()

                Divider()

                // 快捷键设置
                ShortcutSettingsSection()

                Divider()

                // 关于
                AboutSection()
            }
            .padding()
        }
    }

    @ViewBuilder
    private func PermissionStatusSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("权限状态")
                .font(.headline)

            VStack(spacing: 8) {
                PermissionStatusRow(
                    title: "屏幕录制",
                    isGranted: permissionManager.hasScreenRecordingPermission,
                    action: {
                        permissionManager.requestScreenRecordingPermission()
                    }
                )

                PermissionStatusRow(
                    title: "麦克风访问",
                    isGranted: permissionManager.hasMicrophonePermission,
                    action: {
                        permissionManager.requestMicrophonePermission()
                    }
                )

                PermissionStatusRow(
                    title: "辅助功能",
                    isGranted: permissionManager.hasAccessibilityPermission,
                    action: {
                        permissionManager.requestAccessibilityPermission()
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func ScreenshotSettingsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("截图设置")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("自动保存截图", isOn: $autoSaveScreenshots)

                HStack {
                    Text("图片格式:")
                    Spacer()
                    Picker("格式", selection: $screenshotFormat) {
                        Text("PNG").tag("PNG")
                        Text("JPEG").tag("JPEG")
                        Text("TIFF").tag("TIFF")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                HStack {
                    Text("保存位置:")
                    Spacer()
                    Button(defaultSaveLocation.isEmpty ? "选择文件夹" : URL(fileURLWithPath: defaultSaveLocation).lastPathComponent) {
                        selectSaveLocation()
                    }
                    .buttonStyle(.bordered)
                }

                Stepper("延时截图: \(delayedScreenshotSeconds) 秒", value: $delayedScreenshotSeconds, in: 1...30)

                VStack(alignment: .leading, spacing: 6) {
                    Text("长截图")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Stepper("截取屏数: \(scrollingCaptureSlices)", value: $scrollingCaptureSlices, in: 2...20)

                    HStack {
                        Text("滚动间隔:")
                        Slider(value: $scrollingCaptureDelay, in: 0.2...2.0, step: 0.1)
                            .frame(width: 140)
                        Text(String(format: "%.1fs", scrollingCaptureDelay))
                            .foregroundColor(.secondary)
                    }

                    Stepper("每次滚动: \(scrollingCaptureLines) 行", value: $scrollingCaptureLines, in: 3...40)

                    Toggle("自动裁剪重叠区域", isOn: $scrollingCaptureTrimOverlap)
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("截图美化")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Toggle("截图带圆角", isOn: $screenshotRoundedCorners)

                    if screenshotRoundedCorners {
                        HStack {
                            Text("圆角半径:")
                            Slider(value: $screenshotCornerRadius, in: 4...64, step: 1)
                                .frame(width: 140)
                            Text("\(Int(screenshotCornerRadius))")
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle("截图带阴影", isOn: $screenshotDropShadow)

                    if screenshotDropShadow {
                        HStack {
                            Text("阴影大小:")
                            Slider(value: $screenshotShadowRadius, in: 8...80, step: 1)
                                .frame(width: 140)
                            Text("\(Int(screenshotShadowRadius))")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 4)

                HStack {
                    Text("取色格式:")
                    Spacer()
                    Picker("取色格式", selection: $colorCodeFormat) {
                        Text("#HEX").tag("#HEX")
                        Text("RGB").tag("RGB")
                        Text("SwiftUI").tag("SwiftUI")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }

                HStack {
                    Text("截图翻译目标:")
                    Spacer()
                    Picker("截图翻译目标", selection: $translationTargetLanguage) {
                        Text("简体中文").tag("zh-CN")
                        Text("English").tag("en")
                        Text("日本語").tag("ja")
                        Text("한국어").tag("ko")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)
                }

                HStack {
                    Text("指定 App 打开:")
                    Spacer()
                    Button(openAfterCaptureAppPath.isEmpty ? "选择 App" : URL(fileURLWithPath: openAfterCaptureAppPath).deletingPathExtension().lastPathComponent) {
                        selectOpenAfterCaptureApp()
                    }
                    .buttonStyle(.bordered)

                    if !openAfterCaptureAppPath.isEmpty {
                        Button("清除") {
                            openAfterCaptureAppPath = ""
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func RecordingSettingsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("录制设置")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("默认帧率:")
                    Spacer()
                    Picker("帧率", selection: $recordingFrameRate) {
                        Text("15 FPS").tag(15.0)
                        Text("30 FPS").tag(30.0)
                        Text("60 FPS").tag(60.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                HStack {
                    Text("默认质量:")
                    Spacer()
                    Picker("质量", selection: $recordingQuality) {
                        Text("低").tag("低")
                        Text("中").tag("中")
                        Text("高").tag("高")
                        Text("超高").tag("超高")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                HStack {
                    Text("导出格式:")
                    Spacer()
                    Picker("导出格式", selection: $recordingFileFormat) {
                        Text("MOV").tag("MOV")
                        Text("MP4").tag("MP4")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                Stepper("开录延时: \(recordingStartDelaySeconds) 秒", value: $recordingStartDelaySeconds, in: 0...30)
                Toggle("录制系统音频", isOn: $includeSystemAudio)
                Toggle("录制麦克风", isOn: $includeMicrophone)
                Toggle("显示鼠标指针", isOn: $showCursor)
            }
        }
    }

    @ViewBuilder
    private func WindowBehaviorSettingsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("窗口行为")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("截屏时自动隐藏主窗口", isOn: $autoHideWindowDuringCapture)
                    .help("启用后，开始截图或录制时会自动隐藏应用主窗口，避免干扰")

                Toggle("截屏完成后自动显示主窗口", isOn: $autoShowWindowAfterCapture)
                    .help("启用后，截图完成后会自动重新显示应用主窗口")

                if autoHideWindowDuringCapture {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("提示：")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• 可通过状态栏图标或快捷键重新显示窗口")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• 录制时窗口会保持隐藏直到录制结束")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 20)
                }
            }
        }
    }

    @ViewBuilder
    private func FloatingWindowSettingsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("浮窗设置")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("截图后自动显示浮窗", isOn: .constant(true))
                    .help("截图完成后立即显示预览浮窗")

                Toggle("自动复制到剪贴板", isOn: .constant(false))
                    .help("截图后自动将图片复制到系统剪贴板")

                Toggle("始终置顶显示", isOn: .constant(true))
                    .help("浮窗始终显示在其他窗口之上")

                Toggle("显示窗口阴影", isOn: .constant(true))
                    .help("为浮窗添加阴影效果")

                HStack {
                    Text("窗口透明度:")
                    Spacer()
                    Slider(value: .constant(1.0), in: 0.3...1.0, step: 0.1)
                        .frame(width: 120)
                    Text("100%")
                        .frame(width: 40, alignment: .trailing)
                        .foregroundColor(.secondary)
                }
                .help("调整浮窗的透明度")

                HStack {
                    Button("关闭所有浮窗") {
                        // 使用新的EditingWindowManager
                        EditingWindowManager.shared.closeAllWindows()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("最小化所有浮窗") {
                        // 使用新的EditingWindowManager
                        EditingWindowManager.shared.minimizeAllWindows()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Text("活动浮窗: 0") // 暂时显示固定值，等FloatingWindowManager完全集成后再更新
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func GeneralSettingsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("通用设置")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("显示通知", isOn: $showNotifications)
                Toggle("开机自启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(newValue)
                    }
                Toggle("隐藏菜单栏图标", isOn: $hideMenuBarIcon)
            }
        }
    }

    @ViewBuilder
    private func ShortcutSettingsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷键设置")
                .font(.headline)

            // 集成完整的快捷键设置界面
            HotKeySettingsView()
        }
    }

    @ViewBuilder
    private func AboutSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("关于")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("版本:")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("构建:")
                    Spacer()
                    Text("2025.09.25")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Button("检查更新") {
                        // TODO: 实现更新检查
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("反馈问题") {
                        // TODO: 打开反馈页面
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func selectSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择截图保存位置"
        panel.prompt = "选择"

        if panel.runModal() == .OK {
            if let url = panel.url {
                // 开始访问安全作用域资源
                guard url.startAccessingSecurityScopedResource() else {
                    print("无法访问选择的文件夹")
                    return
                }

                // 创建安全作用域书签
                do {
                    let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    UserDefaults.standard.set(bookmarkData, forKey: "defaultSaveLocationBookmark")
                    // 同时保存路径字符串用于显示
                    UserDefaults.standard.set(url.path, forKey: "defaultSaveLocation")
                    defaultSaveLocation = url.path
                    print("成功保存文件夹权限书签: \(url.path)")
                } catch {
                    print("创建书签失败: \(error)")
                }

                // 停止访问安全作用域资源（书签已创建）
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    private func selectOpenAfterCaptureApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "选择用于打开截图的应用"
        panel.prompt = "选择"

        if panel.runModal() == .OK, let url = panel.url {
            openAfterCaptureAppPath = url.path
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        // TODO: 实现开机自启动设置
        print("设置开机自启动: \(enabled)")
    }
}

struct PermissionStatusRow: View {
    let title: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isGranted ? .green : .red)

            Text(title)

            Spacer()

            if !isGranted {
                Button("授权") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Text("已授权")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
    }
}



#Preview {
    SettingsView()
        .environmentObject(PermissionManager())
        .frame(width: 600, height: 400)
}
