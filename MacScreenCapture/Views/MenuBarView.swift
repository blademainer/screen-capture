//
//  MenuBarView.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/25.
//

import SwiftUI
import UserNotifications

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

                MenuButton(title: "延时截图", icon: "timer", shortcut: "⌘⌥L") {
                    quickDelayedScreenshot()
                }

                MenuButton(title: "长截图", icon: "rectangle.expand.vertical", shortcut: "⌘⌥S") {
                    quickScrollingScreenshot()
                }

                MenuButton(title: "多窗口截图", icon: "rectangle.3.group", shortcut: "⌘⌥W") {
                    quickMultiWindowScreenshot()
                }

                MenuButton(title: "全屏带壳截图", icon: "laptopcomputer", shortcut: "⌘⌥F") {
                    quickDeviceFramedScreenshot()
                }
            }

            Divider()

            // 高级工具
            Group {
                MenuButton(title: "取色", icon: "eyedropper", shortcut: "⌘⇧C") {
                    captureManager.pickScreenColor()
                }

                MenuButton(title: "OCR 识别", icon: "text.viewfinder", shortcut: "⌘⌥O") {
                    quickOCR()
                }

                MenuButton(title: "截图翻译", icon: "character.book.closed", shortcut: "⌘⌥T") {
                    quickTranslate()
                }

                MenuButton(title: "贴图", icon: "pin", shortcut: "⌘⌥P") {
                    quickPinnedScreenshot()
                }

                MenuButton(title: "用指定 App 打开", icon: "arrow.up.forward.app") {
                    quickOpenInConfiguredApp()
                }
            }

            Divider()

            // 录制选项
            Group {
                if captureManager.isRecording {
                    MenuButton(
                        title: captureManager.isPaused ? (captureManager.isAudioOnlyRecording ? "恢复录音" : "恢复录制") : (captureManager.isAudioOnlyRecording ? "暂停录音" : "暂停录制"),
                        icon: captureManager.isPaused ? "play.fill" : "pause.fill",
                        shortcut: "⌘⌥Space"
                    ) {
                        captureManager.togglePauseRecording()
                    }

                    MenuButton(
                        title: captureManager.isAudioOnlyRecording ? "停止录音" : "停止录制",
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
                        shortcut: "⌥W"
                    ) {
                        quickRecording()
                    }

                    MenuButton(
                        title: "开始录音",
                        icon: "waveform.circle",
                        shortcut: "⌘⇧M"
                    ) {
                        quickAudioRecording()
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
        .frame(width: 230)
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
                if mode == .window {
                    _ = try await captureManager.captureInteractiveWindowScreenshot()
                } else {
                    _ = try await captureManager.captureScreenshot()
                }
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
                if try await captureManager.startRecordingWithPreflight() {
                    showNotification(title: "录制开始", message: "屏幕录制已开始")
                }
            } catch {
                showNotification(title: "录制失败", message: error.localizedDescription)
            }
        }
    }

    private func quickAudioRecording() {
        guard permissionManager.hasScreenRecordingPermission else {
            permissionManager.requestScreenRecordingPermission()
            return
        }

        Task {
            do {
                if try await captureManager.startAudioRecordingWithPreflight() {
                    showNotification(title: "录音开始", message: "音频录制已开始")
                }
            } catch {
                showNotification(title: "录音失败", message: error.localizedDescription)
            }
        }
    }

    private func quickDelayedScreenshot() {
        guard permissionManager.hasScreenRecordingPermission else {
            permissionManager.requestScreenRecordingPermission()
            return
        }

        Task {
            do {
                let seconds = IShotInteractionTiming.delayedScreenshotSeconds(
                    UserDefaults.standard.integer(forKey: "delayedScreenshotSeconds")
                )
                _ = try await captureManager.captureDelayedScreenshot(seconds: seconds)
                showNotification(title: "延时截图成功", message: "截图已保存")
            } catch {
                showNotification(title: "延时截图失败", message: error.localizedDescription)
            }
        }
    }

    private func quickScrollingScreenshot() {
        guard permissionManager.hasScreenRecordingPermission else {
            permissionManager.requestScreenRecordingPermission()
            return
        }

        Task {
            await captureManager.captureScrollingWindow()
        }
    }

    private func quickMultiWindowScreenshot() {
        guard permissionManager.hasScreenRecordingPermission else {
            permissionManager.requestScreenRecordingPermission()
            return
        }

        Task {
            do {
                _ = try await captureManager.captureMultipleWindowsScreenshot()
                showNotification(title: "多窗口截图成功", message: "截图已保存")
            } catch {
                showNotification(title: "多窗口截图失败", message: error.localizedDescription)
            }
        }
    }

    private func quickDeviceFramedScreenshot() {
        guard permissionManager.hasScreenRecordingPermission else {
            permissionManager.requestScreenRecordingPermission()
            return
        }

        Task {
            do {
                _ = try await captureManager.captureDeviceFramedFullScreen()
                showNotification(title: "带壳截图成功", message: "截图已保存")
            } catch {
                showNotification(title: "带壳截图失败", message: error.localizedDescription)
            }
        }
    }

    private func quickPinnedScreenshot() {
        guard permissionManager.hasScreenRecordingPermission else {
            permissionManager.requestScreenRecordingPermission()
            return
        }

        Task {
            do {
                _ = try await captureManager.capturePinnedRegion()
                showNotification(title: "贴图成功", message: "已创建置顶贴图窗口")
            } catch {
                showNotification(title: "贴图失败", message: error.localizedDescription)
            }
        }
    }

    private func quickOCR() {
        guard permissionManager.hasScreenRecordingPermission else {
            permissionManager.requestScreenRecordingPermission()
            return
        }

        Task {
            do {
                let text = try await captureManager.captureRegionAndRecognizeText()
                showNotification(title: "OCR 完成", message: text.isEmpty ? "未识别到文本" : "识别文本已复制")
            } catch {
                showNotification(title: "OCR 失败", message: error.localizedDescription)
            }
        }
    }

    private func quickTranslate() {
        guard permissionManager.hasScreenRecordingPermission else {
            permissionManager.requestScreenRecordingPermission()
            return
        }

        Task {
            do {
                let result = try await captureManager.captureRegionAndTranslate()
                if result.usedWebFallback {
                    showNotification(title: "截图翻译已打开网页", message: "在线接口不可用，原文已复制（\(result.targetLanguage)）")
                } else {
                    showNotification(title: "截图翻译完成", message: "译文已显示并复制（\(result.targetLanguage)）")
                }
            } catch {
                showNotification(title: "截图翻译失败", message: error.localizedDescription)
            }
        }
    }

    private func quickOpenInConfiguredApp() {
        do {
            try captureManager.openLastScreenshotInConfiguredApp()
        } catch {
            showNotification(title: "打开失败", message: error.localizedDescription)
        }
    }

    private func openMainWindow() {
        WindowManager.shared.showMainWindow()
    }

    private func openSettings() {
        WindowManager.shared.showSettingsTab()
    }

    private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    private func showNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = UNNotificationSound.default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
