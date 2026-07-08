//
//  SettingsView.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/25.
//

import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var permissionManager: PermissionManager
    @AppStorage("autoSaveScreenshots") private var autoSaveScreenshots = true
    @AppStorage("copyScreenshotToClipboard") private var copyScreenshotToClipboard = true
    @AppStorage("screenshotFormat") private var screenshotFormat = "PNG"
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("hideMenuBarIcon") private var hideMenuBarIcon = false
    @AppStorage("defaultSaveLocation") private var defaultSaveLocation = ""
    @AppStorage("autoHideWindowDuringCapture") private var autoHideWindowDuringCapture = true
    @AppStorage("autoShowWindowAfterCapture") private var autoShowWindowAfterCapture = false
    @AppStorage("delayedScreenshotSeconds") private var delayedScreenshotSeconds = 5
    @AppStorage("multiWindowDesktopBackdrop") private var multiWindowDesktopBackdrop = true
    @AppStorage("scrollingCaptureSlices") private var scrollingCaptureSlices = 30
    @AppStorage("scrollingCaptureDelay") private var scrollingCaptureDelay = 0.8
    @AppStorage("scrollingCaptureLines") private var scrollingCaptureLines = 12
    @AppStorage("scrollingCaptureDirection") private var scrollingCaptureDirection = "down"
    @AppStorage("scrollingCaptureTrimOverlap") private var scrollingCaptureTrimOverlap = true
    @AppStorage("scrollingCaptureCropToWindow") private var scrollingCaptureCropToWindow = true
    @AppStorage("scrollingCaptureDetectContentArea") private var scrollingCaptureDetectContentArea = true
    @AppStorage("scrollingCaptureStopWhenUnchanged") private var scrollingCaptureStopWhenUnchanged = true
    @AppStorage("screenshotRoundedCorners") private var screenshotRoundedCorners = false
    @AppStorage("screenshotDropShadow") private var screenshotDropShadow = false
    @AppStorage("showCursorInScreenshots") private var showCursorInScreenshots = false
    @AppStorage("screenshotCornerRadius") private var screenshotCornerRadius = 18.0
    @AppStorage("screenshotShadowRadius") private var screenshotShadowRadius = 24.0
    @AppStorage("screenshotShadowColorHex") private var screenshotShadowColorHex = "#000000"
    @AppStorage("deviceFrameBezelWidth") private var deviceFrameBezelWidth = 42.0
    @AppStorage("deviceFramePadding") private var deviceFramePadding = 48.0
    @AppStorage("deviceFrameCornerRadius") private var deviceFrameCornerRadius = 26.0
    @AppStorage("deviceFrameShadowRadius") private var deviceFrameShadowRadius = 28.0
    @AppStorage("deviceFrameBodyColorHex") private var deviceFrameBodyColorHex = "#141414"
    @AppStorage("deviceFrameShadowColorHex") private var deviceFrameShadowColorHex = "#000000"
    @AppStorage("numberedAnnotationStart") private var numberedAnnotationStart = 1
    @AppStorage("annotationStylePreset") private var annotationStylePreset = AnnotationStylePreset.professional.rawValue
    @AppStorage("annotationDefaultColorHex") private var annotationDefaultColorHex = AnnotationStylePreset.professional.colorHex
    @AppStorage("annotationDefaultLineWidth") private var annotationDefaultLineWidth = AnnotationStylePreset.professional.lineWidth
    @AppStorage("annotationDefaultFontSize") private var annotationDefaultFontSize = AnnotationStylePreset.professional.fontSize
    @AppStorage("annotationTextOutlined") private var annotationTextOutlined = false
    @AppStorage("annotationCustomColorHex") private var annotationCustomColorHex = AnnotationStylePreset.professional.colorHex
    @AppStorage("annotationCustomLineWidth") private var annotationCustomLineWidth = AnnotationStylePreset.professional.lineWidth
    @AppStorage("annotationCustomFontSize") private var annotationCustomFontSize = AnnotationStylePreset.professional.fontSize
    @AppStorage("annotationCustomTextOutlined") private var annotationCustomTextOutlined = false
    @AppStorage("annotationCustom2ColorHex") private var annotationCustom2ColorHex = AnnotationStylePreset.professional.colorHex
    @AppStorage("annotationCustom2LineWidth") private var annotationCustom2LineWidth = AnnotationStylePreset.professional.lineWidth
    @AppStorage("annotationCustom2FontSize") private var annotationCustom2FontSize = AnnotationStylePreset.professional.fontSize
    @AppStorage("annotationCustom2TextOutlined") private var annotationCustom2TextOutlined = false
    @AppStorage("annotationCustom3ColorHex") private var annotationCustom3ColorHex = AnnotationStylePreset.professional.colorHex
    @AppStorage("annotationCustom3LineWidth") private var annotationCustom3LineWidth = AnnotationStylePreset.professional.lineWidth
    @AppStorage("annotationCustom3FontSize") private var annotationCustom3FontSize = AnnotationStylePreset.professional.fontSize
    @AppStorage("annotationCustom3TextOutlined") private var annotationCustom3TextOutlined = false
    @AppStorage("colorCodeFormat") private var colorCodeFormat = "#HEX"
    @AppStorage("customColorCodeTemplate") private var customColorCodeTemplate = "{hex}"
    @AppStorage("openAfterCaptureAppPath") private var openAfterCaptureAppPath = ""
    @AppStorage("autoOpenAfterCaptureInConfiguredApp") private var autoOpenAfterCaptureInConfiguredApp = false
    @AppStorage("doubleOptionQuickOpenEnabled") private var doubleOptionQuickOpenEnabled = true
    @AppStorage("doubleOptionQuickOpenInterval") private var doubleOptionQuickOpenInterval = 0.45
    @AppStorage("doubleOptionQuickOpenCooldown") private var doubleOptionQuickOpenCooldown = 1.0
    @AppStorage("translationTargetLanguage") private var translationTargetLanguage = "zh-CN"
    @AppStorage("recordingFrameRate") private var recordingFrameRate = 60.0
    @AppStorage("recordingQuality") private var recordingQuality = "高"
    @AppStorage("includeSystemAudio") private var includeSystemAudio = true
    @AppStorage("includeMicrophone") private var includeMicrophone = true
    @AppStorage("showCursor") private var showCursor = true
    @AppStorage("recordingStartDelaySeconds") private var recordingStartDelaySeconds = 0
    @AppStorage("recordingFileFormat") private var recordingFileFormat = "MOV"
    @AppStorage("autoCopyToClipboard") private var autoCopyToClipboard = false
    @AppStorage("floatingWindowAlwaysOnTop") private var floatingWindowAlwaysOnTop = true
    @AppStorage("floatingWindowShowShadow") private var floatingWindowShowShadow = true
    @AppStorage("floatingWindowOpacity") private var floatingWindowOpacity = 0.95
    @AppStorage("floatingWindowCloseAfterSave") private var floatingWindowCloseAfterSave = false
    @ObservedObject private var floatingWindowManager = FloatingWindowManager.shared
    @State private var isPreparingTranslationModels = false
    @State private var translationModelStatusMessage = ""
    @State private var annotationTemplateTransferMessage = ""
    @State private var generalSettingsMessage = ""

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
                Toggle("截图后自动复制到剪贴板", isOn: $copyScreenshotToClipboard)
                    .help("截图完成后默认将最终图片写入系统剪贴板")
                Toggle("截图包含鼠标指针", isOn: $showCursorInScreenshots)
                    .help("关闭后截图不会包含系统当前鼠标样式，避免把圆形指针截进图片")

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

                Toggle("多窗口截图使用桌面底板", isOn: $multiWindowDesktopBackdrop)

                VStack(alignment: .leading, spacing: 6) {
                    Text("长截图")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Stepper("最多截取屏数: \(scrollingCaptureSlices)", value: $scrollingCaptureSlices, in: 2...100)

                    HStack {
                        Text("滚动间隔:")
                        Slider(value: $scrollingCaptureDelay, in: 0.2...2.0, step: 0.1)
                            .frame(width: 140)
                        Text(String(format: "%.1fs", scrollingCaptureDelay))
                            .foregroundColor(.secondary)
                    }

                    Stepper("每次滚动: \(scrollingCaptureLines) 行", value: $scrollingCaptureLines, in: 3...40)

                    HStack {
                        Text("滚动方向:")
                        Spacer()
                        Picker("滚动方向", selection: $scrollingCaptureDirection) {
                            Text("向下").tag("down")
                            Text("向上").tag("up")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 132)
                    }

                    Toggle("裁剪到鼠标所在窗口", isOn: $scrollingCaptureCropToWindow)

                    if scrollingCaptureCropToWindow {
                        Toggle("优先识别窗口内滚动内容区", isOn: $scrollingCaptureDetectContentArea)
                    }

                    Toggle("滚动到底自动停止", isOn: $scrollingCaptureStopWhenUnchanged)

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

                        HStack {
                            Text("阴影颜色:")
                            Spacer()
                            TextField("#000000", text: $screenshotShadowColorHex)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                        }
                    }
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("全屏带壳截图")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack {
                        Text("外壳厚度:")
                        Slider(value: $deviceFrameBezelWidth, in: 18...96, step: 1)
                            .frame(width: 140)
                        Text("\(Int(deviceFrameBezelWidth))")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("画布留白:")
                        Slider(value: $deviceFramePadding, in: 16...120, step: 1)
                            .frame(width: 140)
                        Text("\(Int(deviceFramePadding))")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("外壳圆角:")
                        Slider(value: $deviceFrameCornerRadius, in: 8...64, step: 1)
                            .frame(width: 140)
                        Text("\(Int(deviceFrameCornerRadius))")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("阴影大小:")
                        Slider(value: $deviceFrameShadowRadius, in: 0...80, step: 1)
                            .frame(width: 140)
                        Text("\(Int(deviceFrameShadowRadius))")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("外壳颜色:")
                        Spacer()
                        TextField("#141414", text: $deviceFrameBodyColorHex)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                    }

                    HStack {
                        Text("阴影颜色:")
                        Spacer()
                        TextField("#000000", text: $deviceFrameShadowColorHex)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                    }
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("标注")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack {
                        Text("样式模板:")
                        Spacer()
                        Picker("样式模板", selection: $annotationStylePreset) {
                            ForEach(AnnotationStylePreset.allCases, id: \.rawValue) { preset in
                                Text(preset.displayName).tag(preset.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        .onChange(of: annotationStylePreset) { presetValue in
                            applyAnnotationPreset(presetValue)
                        }
                    }

                    Stepper("数字序号起始值: \(numberedAnnotationStart)", value: $numberedAnnotationStart, in: 1...999)
                    HStack {
                        Text("默认颜色:")
                        Spacer()
                        TextField("#FF3B30", text: $annotationDefaultColorHex)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                    }
                    HStack {
                        Text("默认粗细:")
                        Slider(value: $annotationDefaultLineWidth, in: 1...10, step: 1)
                            .frame(width: 140)
                        Text("\(Int(annotationDefaultLineWidth))")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("默认字号:")
                        Slider(value: $annotationDefaultFontSize, in: 10...72, step: 1)
                            .frame(width: 140)
                        Text("\(Int(annotationDefaultFontSize))")
                            .foregroundColor(.secondary)
                    }
                    Toggle("文字和序号启用描边", isOn: $annotationTextOutlined)
                    HStack {
                        Spacer()
                        Button("存为自定义 1") {
                            saveCustomAnnotationPreset(.custom)
                        }
                        .buttonStyle(.bordered)
                        Button("存为自定义 2") {
                            saveCustomAnnotationPreset(.custom2)
                        }
                        .buttonStyle(.bordered)
                        Button("存为自定义 3") {
                            saveCustomAnnotationPreset(.custom3)
                        }
                        .buttonStyle(.bordered)
                    }
                    HStack {
                        Spacer()
                        Button("导出模板") {
                            exportAnnotationTemplates()
                        }
                        .buttonStyle(.bordered)
                        Button("导入模板") {
                            importAnnotationTemplates()
                        }
                        .buttonStyle(.bordered)
                    }

                    if !annotationTemplateTransferMessage.isEmpty {
                        Text(annotationTemplateTransferMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                        Text("自定义").tag("Custom")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }

                if colorCodeFormat == "Custom" {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("自定义色码模板", text: $customColorCodeTemplate)
                            .textFieldStyle(.roundedBorder)
                        Text("可用占位符：{hex} {rgb} {r255} {g255} {b255} {r} {g} {b}")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
                    Text("本地翻译模型:")
                    Spacer()
                    Button(isPreparingTranslationModels ? "检查中..." : "检查并准备") {
                        prepareLocalTranslationModels()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isPreparingTranslationModels)
                }

                if !translationModelStatusMessage.isEmpty {
                    Text(translationModelStatusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

                Toggle("截图保存后自动用指定 App 打开", isOn: $autoOpenAfterCaptureInConfiguredApp)

                Toggle("双击 ⌥ 后截图并打开指定 App", isOn: $doubleOptionQuickOpenEnabled)

                if autoOpenAfterCaptureInConfiguredApp || doubleOptionQuickOpenEnabled {
                    if openAfterCaptureAppPath.isEmpty {
                        Text("未选择指定 App 时会用系统默认 App 打开。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if doubleOptionQuickOpenEnabled {
                    HStack {
                        Text("双击判定:")
                        Slider(value: $doubleOptionQuickOpenInterval, in: 0.25...1.2, step: 0.05)
                            .frame(width: 140)
                        Text(String(format: "%.2fs", doubleOptionQuickOpenInterval))
                            .foregroundColor(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }

                    HStack {
                        Text("触发冷却:")
                        Slider(value: $doubleOptionQuickOpenCooldown, in: 0.5...3.0, step: 0.1)
                            .frame(width: 140)
                        Text(String(format: "%.1fs", doubleOptionQuickOpenCooldown))
                            .foregroundColor(.secondary)
                            .frame(width: 48, alignment: .trailing)
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
                Toggle("录屏显示鼠标指针", isOn: $showCursor)
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
                Toggle("自动复制到剪贴板", isOn: $autoCopyToClipboard)
                    .help("截图后自动将图片复制到系统剪贴板")

                Toggle("始终置顶显示", isOn: $floatingWindowAlwaysOnTop)
                    .help("浮窗始终显示在其他窗口之上")

                Toggle("显示窗口阴影", isOn: $floatingWindowShowShadow)
                    .help("为浮窗添加阴影效果")

                Toggle("保存后自动关闭浮窗", isOn: $floatingWindowCloseAfterSave)
                    .help("保存贴图后自动关闭对应浮窗")

                HStack {
                    Text("窗口透明度:")
                    Spacer()
                    Slider(value: $floatingWindowOpacity, in: 0.3...1.0, step: 0.05)
                        .frame(width: 120)
                    Text("\(Int(floatingWindowOpacity * 100))%")
                        .frame(width: 40, alignment: .trailing)
                        .foregroundColor(.secondary)
                }
                .help("调整浮窗的透明度")

                HStack {
                    Button("关闭所有浮窗") {
                        floatingWindowManager.closeAllWindows()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("最小化所有浮窗") {
                        floatingWindowManager.minimizeAllWindows()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Text("活动浮窗: \(floatingWindowManager.activeWindows.count)")
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
                    .onChange(of: hideMenuBarIcon) { newValue in
                        WindowManager.shared.setStatusBarIconHidden(newValue)
                    }

                if !generalSettingsMessage.isEmpty {
                    Text(generalSettingsMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
                        openExternalURL("https://github.com/blademainer/screen-capture/releases")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("反馈问题") {
                        openExternalURL("https://github.com/blademainer/screen-capture/issues")
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
        panel.canCreateDirectories = true
        panel.message = "选择截图保存位置"
        panel.prompt = "选择"

        if runSettingsPanel(panel) == .OK {
            if let url = panel.url {
                let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccessSecurityScope {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    UserDefaults.standard.set(bookmarkData, forKey: "defaultSaveLocationBookmark")
                    print("成功保存文件夹权限书签: \(url.path)")
                } catch {
                    print("创建书签失败: \(error)")
                }

                UserDefaults.standard.set(url.path, forKey: "defaultSaveLocation")
                defaultSaveLocation = url.path
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

        if runSettingsPanel(panel) == .OK, let url = panel.url {
            openAfterCaptureAppPath = url.path
        }
    }

    private func applyAnnotationPreset(_ presetValue: String) {
        guard let preset = AnnotationStylePreset(rawValue: presetValue) else { return }
        switch preset {
        case .custom:
            annotationDefaultColorHex = annotationCustomColorHex
            annotationDefaultLineWidth = annotationCustomLineWidth
            annotationDefaultFontSize = annotationCustomFontSize
            annotationTextOutlined = annotationCustomTextOutlined
            return
        case .custom2:
            annotationDefaultColorHex = annotationCustom2ColorHex
            annotationDefaultLineWidth = annotationCustom2LineWidth
            annotationDefaultFontSize = annotationCustom2FontSize
            annotationTextOutlined = annotationCustom2TextOutlined
            return
        case .custom3:
            annotationDefaultColorHex = annotationCustom3ColorHex
            annotationDefaultLineWidth = annotationCustom3LineWidth
            annotationDefaultFontSize = annotationCustom3FontSize
            annotationTextOutlined = annotationCustom3TextOutlined
            return
        default:
            break
        }

        annotationDefaultColorHex = preset.colorHex
        annotationDefaultLineWidth = preset.lineWidth
        annotationDefaultFontSize = preset.fontSize
        annotationTextOutlined = preset.textOutlined
    }

    private func saveCustomAnnotationPreset(_ preset: AnnotationStylePreset) {
        switch preset {
        case .custom:
            annotationCustomColorHex = annotationDefaultColorHex
            annotationCustomLineWidth = annotationDefaultLineWidth
            annotationCustomFontSize = annotationDefaultFontSize
            annotationCustomTextOutlined = annotationTextOutlined
        case .custom2:
            annotationCustom2ColorHex = annotationDefaultColorHex
            annotationCustom2LineWidth = annotationDefaultLineWidth
            annotationCustom2FontSize = annotationDefaultFontSize
            annotationCustom2TextOutlined = annotationTextOutlined
        case .custom3:
            annotationCustom3ColorHex = annotationDefaultColorHex
            annotationCustom3LineWidth = annotationDefaultLineWidth
            annotationCustom3FontSize = annotationDefaultFontSize
            annotationCustom3TextOutlined = annotationTextOutlined
        default:
            return
        }

        annotationStylePreset = preset.rawValue
    }

    private func exportAnnotationTemplates() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MacScreenCapture-Annotation-Templates.json"
        panel.message = "导出 3 套自定义标注模板"
        panel.prompt = "导出"

        guard runSettingsPanel(panel) == .OK, let url = panel.url else { return }

        let payload = AnnotationTemplateExport(
            version: 1,
            templates: [
                annotationTemplatePayload(name: "自定义 1", colorHex: annotationCustomColorHex, lineWidth: annotationCustomLineWidth, fontSize: annotationCustomFontSize, textOutlined: annotationCustomTextOutlined),
                annotationTemplatePayload(name: "自定义 2", colorHex: annotationCustom2ColorHex, lineWidth: annotationCustom2LineWidth, fontSize: annotationCustom2FontSize, textOutlined: annotationCustom2TextOutlined),
                annotationTemplatePayload(name: "自定义 3", colorHex: annotationCustom3ColorHex, lineWidth: annotationCustom3LineWidth, fontSize: annotationCustom3FontSize, textOutlined: annotationCustom3TextOutlined)
            ]
        )

        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: .atomic)
            annotationTemplateTransferMessage = "已导出标注模板。"
        } catch {
            annotationTemplateTransferMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func importAnnotationTemplates() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.message = "导入自定义标注模板"
        panel.prompt = "导入"

        guard runSettingsPanel(panel) == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(AnnotationTemplateExport.self, from: data)
            guard payload.templates.count >= 3 else {
                annotationTemplateTransferMessage = "导入失败：模板文件至少需要 3 套模板。"
                return
            }

            applyAnnotationTemplate(payload.templates[0], to: .custom)
            applyAnnotationTemplate(payload.templates[1], to: .custom2)
            applyAnnotationTemplate(payload.templates[2], to: .custom3)
            applyAnnotationPreset(annotationStylePreset)
            annotationTemplateTransferMessage = "已导入标注模板。"
        } catch {
            annotationTemplateTransferMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    private func annotationTemplatePayload(name: String, colorHex: String, lineWidth: Double, fontSize: Double, textOutlined: Bool) -> AnnotationTemplatePayload {
        AnnotationTemplatePayload(
            name: name,
            colorHex: normalizedAnnotationHex(colorHex),
            lineWidth: min(max(lineWidth, 1), 10),
            fontSize: min(max(fontSize, 10), 72),
            textOutlined: textOutlined
        )
    }

    private func applyAnnotationTemplate(_ template: AnnotationTemplatePayload, to preset: AnnotationStylePreset) {
        let colorHex = normalizedAnnotationHex(template.colorHex)
        let lineWidth = min(max(template.lineWidth, 1), 10)
        let fontSize = min(max(template.fontSize ?? AnnotationStylePreset.professional.fontSize, 10), 72)

        switch preset {
        case .custom:
            annotationCustomColorHex = colorHex
            annotationCustomLineWidth = lineWidth
            annotationCustomFontSize = fontSize
            annotationCustomTextOutlined = template.textOutlined
        case .custom2:
            annotationCustom2ColorHex = colorHex
            annotationCustom2LineWidth = lineWidth
            annotationCustom2FontSize = fontSize
            annotationCustom2TextOutlined = template.textOutlined
        case .custom3:
            annotationCustom3ColorHex = colorHex
            annotationCustom3LineWidth = lineWidth
            annotationCustom3FontSize = fontSize
            annotationCustom3TextOutlined = template.textOutlined
        default:
            break
        }
    }

    private func normalizedAnnotationHex(_ value: String) -> String {
        var clean = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }

        guard clean.count == 6, Int(clean, radix: 16) != nil else {
            return AnnotationStylePreset.professional.colorHex
        }

        return "#\(clean)"
    }

    private func prepareLocalTranslationModels() {
        isPreparingTranslationModels = true
        translationModelStatusMessage = "正在检查 Apple 本地翻译模型..."

        Task {
            let message = await CaptureManager.shared.prepareAppleTranslationModels(
                targetLanguage: translationTargetLanguage
            )
            await MainActor.run {
                translationModelStatusMessage = message
                isPreparingTranslationModels = false
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            generalSettingsMessage = "当前系统不支持在应用内设置开机自启动。"
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
                generalSettingsMessage = "已开启开机自启动。"
            } else {
                try SMAppService.mainApp.unregister()
                generalSettingsMessage = "已关闭开机自启动。"
            }
        } catch {
            generalSettingsMessage = "开机自启动设置失败：\(error.localizedDescription)"
        }
    }

    private func runSettingsPanel(_ panel: NSSavePanel) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        panel.level = .floating
        panel.orderFrontRegardless()
        return panel.runModal()
    }

    private func openExternalURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct AnnotationTemplateExport: Codable {
    let version: Int
    let templates: [AnnotationTemplatePayload]
}

private struct AnnotationTemplatePayload: Codable {
    let name: String
    let colorHex: String
    let lineWidth: Double
    let fontSize: Double?
    let textOutlined: Bool
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
