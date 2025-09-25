//
//  NotificationManager.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/25.
//

import Foundation
import UserNotifications
import AppKit

/// 通知管理器 - 负责处理应用内通知和系统通知
@MainActor
class NotificationManager: ObservableObject {
    
    // MARK: - Singleton
    static let shared = NotificationManager()
    
    // MARK: - Published Properties
    @Published var hasNotificationPermission = false
    @Published var notificationsEnabled = true
    
    // MARK: - Private Properties
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // MARK: - Initialization
    private init() {
        setupNotificationCenter()
        checkNotificationPermission()
    }
    
    // MARK: - Public Methods
    
    /// 请求通知权限
    func requestNotificationPermission() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.hasNotificationPermission = granted
                if let error = error {
                    print("通知权限请求失败: \(error)")
                }
            }
        }
    }
    
    /// 显示截图成功通知
    func showScreenshotSuccessNotification(filePath: URL) {
        guard notificationsEnabled && hasNotificationPermission else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "截图成功"
        content.body = "截图已保存到 \(filePath.lastPathComponent)"
        content.sound = .default
        content.userInfo = ["filePath": filePath.path, "type": "screenshot"]
        
        // 添加操作按钮
        let showAction = UNNotificationAction(
            identifier: "show_in_finder",
            title: "在Finder中显示",
            options: []
        )
        
        let copyAction = UNNotificationAction(
            identifier: "copy_to_clipboard",
            title: "复制到剪贴板",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "screenshot_success",
            actions: [showAction, copyAction],
            intentIdentifiers: [],
            options: []
        )
        
        notificationCenter.setNotificationCategories([category])
        content.categoryIdentifier = "screenshot_success"
        
        let request = UNNotificationRequest(
            identifier: "screenshot_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("显示截图通知失败: \(error)")
            }
        }
    }
    
    /// 显示录制开始通知
    func showRecordingStartNotification() {
        guard notificationsEnabled && hasNotificationPermission else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "录制开始"
        content.body = "屏幕录制已开始"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "recording_start_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("显示录制开始通知失败: \(error)")
            }
        }
    }
    
    /// 显示录制完成通知
    func showRecordingCompleteNotification(filePath: URL, duration: TimeInterval) {
        guard notificationsEnabled && hasNotificationPermission else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "录制完成"
        content.body = "录制时长 \(formatDuration(duration))，已保存到 \(filePath.lastPathComponent)"
        content.sound = .default
        content.userInfo = ["filePath": filePath.path, "type": "recording"]
        
        // 添加操作按钮
        let showAction = UNNotificationAction(
            identifier: "show_in_finder",
            title: "在Finder中显示",
            options: []
        )
        
        let playAction = UNNotificationAction(
            identifier: "play_video",
            title: "播放视频",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "recording_complete",
            actions: [showAction, playAction],
            intentIdentifiers: [],
            options: []
        )
        
        notificationCenter.setNotificationCategories([category])
        content.categoryIdentifier = "recording_complete"
        
        let request = UNNotificationRequest(
            identifier: "recording_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("显示录制完成通知失败: \(error)")
            }
        }
    }
    
    /// 显示错误通知
    func showErrorNotification(title: String, message: String) {
        guard notificationsEnabled && hasNotificationPermission else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .defaultCritical
        
        let request = UNNotificationRequest(
            identifier: "error_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("显示错误通知失败: \(error)")
            }
        }
    }
    
    /// 显示权限提醒通知
    func showPermissionReminderNotification() {
        guard notificationsEnabled && hasNotificationPermission else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "需要权限"
        content.body = "请在系统偏好设置中授予屏幕录制权限"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "permission_reminder_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("显示权限提醒通知失败: \(error)")
            }
        }
    }
    
    /// 清除所有通知
    func clearAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
    }
    
    // MARK: - Private Methods
    
    /// 设置通知中心
    private func setupNotificationCenter() {
        notificationCenter.delegate = self
    }
    
    /// 检查通知权限
    private func checkNotificationPermission() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.hasNotificationPermission = settings.authorizationStatus == .authorized
            }
        }
    }
    
    /// 格式化时长
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    
    /// 应用在前台时显示通知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
    
    /// 处理通知响应
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        switch response.actionIdentifier {
        case "show_in_finder":
            if let filePath = userInfo["filePath"] as? String {
                let url = URL(fileURLWithPath: filePath)
                FileManager.showInFinder(url)
            }
            
        case "copy_to_clipboard":
            if let filePath = userInfo["filePath"] as? String {
                let url = URL(fileURLWithPath: filePath)
                if userInfo["type"] as? String == "screenshot" {
                    // 复制图片到剪贴板
                    if let image = NSImage(contentsOf: url) {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setData(image.tiffRepresentation, forType: .tiff)
                    }
                } else {
                    // 复制文件路径到剪贴板
                    FileManager.copyToClipboard(url)
                }
            }
            
        case "play_video":
            if let filePath = userInfo["filePath"] as? String {
                let url = URL(fileURLWithPath: filePath)
                NSWorkspace.shared.open(url)
            }
            
        default:
            break
        }
        
        completionHandler()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let screenshotSaved = Notification.Name("screenshotSaved")
    static let recordingStarted = Notification.Name("recordingStarted")
    static let recordingCompleted = Notification.Name("recordingCompleted")
    static let captureError = Notification.Name("captureError")
}