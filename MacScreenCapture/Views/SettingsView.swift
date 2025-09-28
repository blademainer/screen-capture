//
//  SettingsView.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/25.
//

import SwiftUI

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
                if #available(macOS 12.3, *) {
                    if #available(macOS 12.3, *) {
                    ShortcutSettingsSection()
                }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("快捷键设置")
                            .font(.headline)
                        Text("快捷键设置需要 macOS 12.3 或更高版本")
                            .foregroundColor(.secondary)
                    }
                }
                
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
                    Picker("帧率", selection: .constant(60)) {
                        Text("30 FPS").tag(30)
                        Text("60 FPS").tag(60)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                
                HStack {
                    Text("默认质量:")
                    Spacer()
                    Picker("质量", selection: .constant("高")) {
                        Text("低").tag("低")
                        Text("中").tag("中")
                        Text("高").tag("高")
                        Text("超高").tag("超高")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                
                Toggle("默认录制音频", isOn: .constant(true))
                Toggle("显示鼠标指针", isOn: .constant(true))
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
                        // 关闭所有浮窗的功能暂时注释，因为FloatingWindowManager还未完全集成
                        // FloatingWindowManager.shared.closeAllWindows()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("最小化所有浮窗") {
                        // 最小化所有浮窗的功能暂时注释，因为FloatingWindowManager还未完全集成
                        // FloatingWindowManager.shared.minimizeAllWindows()
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
    @available(macOS 12.3, *)
    private func ShortcutSettingsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷键设置")
                .font(.headline)
            
            // 集成完整的快捷键设置界面
            if #available(macOS 12.3, *) {
                HotKeySettingsView()
            } else {
                Text("快捷键设置需要 macOS 12.3 或更高版本")
                    .foregroundColor(.secondary)
            }
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