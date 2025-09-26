//
//  MenuBarView.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/25.
//

import SwiftUI

@available(macOS 12.3, *)
struct MenuBarView: View {
    @EnvironmentObject var captureManager: CaptureManager
    @EnvironmentObject var permissionManager: PermissionManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 快速截图选项
            Group {
                MenuButton(
                    title: "全屏截图",
                    icon: "display",
                    shortcut: "⌘⇧S"
                ) {
                    quickScreenshot(.fullScreen)
                }
                
                MenuButton(
                    title: "窗口截图",
                    icon: "macwindow",
                    shortcut: "⌘⇧W"
                ) {
                    quickScreenshot(.window)
                }
                
                MenuButton(
                    title: "区域截图",
                    icon: "crop",
                    shortcut: "⌘⇧A"
                ) {
                    quickScreenshot(.region)
                }
            }
            
            Divider()
            
            // 录制选项
            Group {
                if captureManager.isRecording {
                    MenuButton(
                        title: captureManager.isPaused ? "恢复录制" : "暂停录制",
                        icon: captureManager.isPaused ? "play.fill" : "pause.fill",
                        shortcut: "⌘Space"
                    ) {
                        captureManager.togglePauseRecording()
                    }
                    
                    MenuButton(
                        title: "停止录制",
                        icon: "stop.fill",
                        shortcut: "⌘⇧R"
                    ) {
                        Task {
                            await captureManager.stopRecording()
                        }
                    }
                    
                    // 录制状态显示
                    HStack {
                        Circle()
                            .fill(captureManager.isPaused ? Color.orange : Color.red)
                            .frame(width: 8, height: 8)
                        
                        Text(formatDuration(captureManager.recordingDuration))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    
                } else {
                    MenuButton(
                        title: "开始录制",
                        icon: "record.circle",
                        shortcut: "⌘⇧R"
                    ) {
                        quickRecording()
                    }
                }
            }
            
            Divider()
            
            // 应用选项
            Group {
                MenuButton(
                    title: "打开主窗口",
                    icon: "app.badge"
                ) {
                    openMainWindow()
                }
                
                MenuButton(
                    title: "偏好设置",
                    icon: "gear"
                ) {
                    openSettings()
                }
                
                MenuButton(
                    title: "关于",
                    icon: "info.circle"
                ) {
                    showAbout()
                }
            }
            
            Divider()
            
            MenuButton(
                title: "退出",
                icon: "power",
                destructive: true
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(width: 200)
    }
    
    private func quickScreenshot(_ mode: CaptureMode) {
        guard permissionManager.hasScreenRecordingPermission else {
            permissionManager.requestScreenRecordingPermission()
            return
        }
        
        Task {
            let oldMode = captureManager.captureMode
            captureManager.captureMode = mode
            
            do {
                _ = try await captureManager.captureScreenshot()
                // 显示成功通知
                showNotification(title: "截图成功", message: "截图已保存")
            } catch {
                // 显示错误通知
                showNotification(title: "截图失败", message: error.localizedDescription)
            }
            
            captureManager.captureMode = oldMode
        }
    }
    
    private func quickRecording() {
        guard permissionManager.hasScreenRecordingPermission else {
            permissionManager.requestScreenRecordingPermission()
            return
        }
        
        Task {
            do {
                try await captureManager.startRecording()
                showNotification(title: "录制开始", message: "屏幕录制已开始")
            } catch {
                showNotification(title: "录制失败", message: error.localizedDescription)
            }
        }
    }
    
    private func openMainWindow() {
        // 激活应用并显示主窗口
        NSApp.activate(ignoringOtherApps: true)
        
        // 如果没有窗口，创建一个新的
        if NSApp.windows.isEmpty {
            // TODO: 创建新的主窗口
        } else {
            // 显示现有窗口
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
    
    private func openSettings() {
        openMainWindow()
        // TODO: 切换到设置标签页
    }
    
    private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
    
    private func showNotification(title: String, message: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message
        notification.soundName = NSUserNotificationDefaultSoundName
        
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct MenuButton: View {
    let title: String
    let icon: String
    let shortcut: String?
    let destructive: Bool
    let action: () -> Void
    
    init(
        title: String,
        icon: String,
        shortcut: String? = nil,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.shortcut = shortcut
        self.destructive = destructive
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundColor(destructive ? .red : .primary)
                
                Text(title)
                    .foregroundColor(destructive ? .red : .primary)
                
                Spacer()
                
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

#Preview {
    if #available(macOS 12.3, *) {
        MenuBarView()
            .environmentObject(CaptureManager())
            .environmentObject(PermissionManager())
    } else {
        Text("需要 macOS 12.3 或更高版本")
    }
}