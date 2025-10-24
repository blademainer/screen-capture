//
//  PermissionManager.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/25.
//

import Foundation
import AVFoundation
@preconcurrency import ScreenCaptureKit
import AppKit

/// 权限管理器 - 负责处理所有系统权限相关的功能
@MainActor
class PermissionManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var hasScreenRecordingPermission = false
    @Published var hasMicrophonePermission = false
    @Published var hasAccessibilityPermission = false
    @Published var permissionCheckInProgress = false
    
    // MARK: - Private Properties
    private var permissionCheckTimer: Timer?
    
    // MARK: - Initialization
    init() {
        startPermissionMonitoring()
    }
    
    deinit {
        permissionCheckTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    /// 检查所有权限状态
    func checkAllPermissions() {
        Task {
            await checkScreenRecordingPermission()
            await checkMicrophonePermission()
            await checkAccessibilityPermission()
        }
    }
    
    /// 请求屏幕录制权限
    func requestScreenRecordingPermission() {
        guard !hasScreenRecordingPermission else { return }
        
        permissionCheckInProgress = true
        
        // 使用ScreenCaptureKit检查权限
        if #available(macOS 12.3, *) {
            Task {
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(
                        false,
                        onScreenWindowsOnly: true
                    )
                    
                    // 如果能获取到内容，说明有权限
                    await MainActor.run {
                        self.hasScreenRecordingPermission = !content.displays.isEmpty
                        self.permissionCheckInProgress = false
                    }
                } catch {
                    await MainActor.run {
                        self.hasScreenRecordingPermission = false
                        self.permissionCheckInProgress = false
                        // self.showPermissionAlert(for: .screenRecording)
                    }
                }
            }
        } else {
            // 对于较旧的系统，使用CGDisplayStream检查
            checkLegacyScreenRecordingPermission()
        }
    }
    
    /// 请求麦克风权限
    func requestMicrophonePermission() {
        guard !hasMicrophonePermission else { return }
        
        // macOS 使用不同的音频权限检查方式
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasMicrophonePermission = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.hasMicrophonePermission = granted
                    if !granted {
                        self?.showPermissionAlert(for: .microphone)
                    }
                }
            }
        case .denied, .restricted:
            hasMicrophonePermission = false
            showPermissionAlert(for: .microphone)
        @unknown default:
            hasMicrophonePermission = false
        }
    }
    
    /// 异步请求麦克风权限并等待结果
    func requestMicrophonePermissionAsync() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            await MainActor.run {
                self.hasMicrophonePermission = true
            }
            return true
            
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run {
                self.hasMicrophonePermission = granted
                if !granted {
                    self.showPermissionAlert(for: .microphone)
                }
            }
            return granted
            
        case .denied, .restricted:
            await MainActor.run {
                self.hasMicrophonePermission = false
                self.showPermissionAlert(for: .microphone)
            }
            return false
            
        @unknown default:
            await MainActor.run {
                self.hasMicrophonePermission = false
            }
            return false
        }
    }
    
    /// 检查麦克风设备是否可用
    func checkMicrophoneDeviceAvailable() -> Bool {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = discoverySession.devices
        
        logToFile("检测到的音频设备数量: \(devices.count)")
        for (index, device) in devices.enumerated() {
            logToFile("  设备 \(index + 1): \(device.localizedName)")
        }
        
        return !devices.isEmpty
    }
    
    /// 写入日志到桌面文件
    private func logToFile(_ message: String) {
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let logFileURL = desktopURL.appendingPathComponent("MacScreenCapture_Microphone_Debug.log")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] [INFO] \(message)\n"
        
        print("🎤 \(logMessage.trimmingCharacters(in: .newlines))")
        
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
    
    /// 请求辅助功能权限
    func requestAccessibilityPermission() {
        guard !hasAccessibilityPermission else { return }
        
        let trusted = AXIsProcessTrusted()
        hasAccessibilityPermission = trusted
        
        if !trusted {
            // showPermissionAlert(for: .accessibility)
        }
    }
    
    // MARK: - Private Methods
    
    /// 检查屏幕录制权限
    private func checkScreenRecordingPermission() async {
        if #available(macOS 12.3, *) {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )
                hasScreenRecordingPermission = !content.displays.isEmpty
            } catch {
                hasScreenRecordingPermission = false
            }
        } else {
            checkLegacyScreenRecordingPermission()
        }
    }
    
    /// 检查麦克风权限
    private func checkMicrophonePermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        hasMicrophonePermission = (status == .authorized)
    }
    
    /// 检查辅助功能权限
    private func checkAccessibilityPermission() async {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }
    
    /// 使用 ScreenCaptureKit 检查屏幕录制权限
    private func checkLegacyScreenRecordingPermission() {
        Task {
            do {
                // 尝试获取可共享内容来检查权限
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                await MainActor.run {
                    hasScreenRecordingPermission = true
                }
            } catch {
                await MainActor.run {
                    hasScreenRecordingPermission = false
                }
            }
        }
        
        permissionCheckInProgress = false
    }
    
    /// 开始权限监控
    private func startPermissionMonitoring() {
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAllPermissions()
            }
        }
    }
    
    /// 显示权限提示对话框
    private func showPermissionAlert(for permission: PermissionType) {
        let alert = NSAlert()
        alert.messageText = permission.alertTitle
        alert.informativeText = permission.alertMessage
        alert.addButton(withTitle: "打开系统偏好设置")
        alert.addButton(withTitle: "稍后")
        alert.alertStyle = .warning
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openSystemPreferences(for: permission)
        }
    }
    
    /// 打开系统偏好设置
    private func openSystemPreferences(for permission: PermissionType) {
        let url: String
        
        switch permission {
        case .screenRecording:
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .microphone:
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
        
        if let settingsURL = URL(string: url) {
            NSWorkspace.shared.open(settingsURL)
        }
    }
}

// MARK: - Permission Types

enum PermissionType {
    case screenRecording
    case microphone
    case accessibility
    
    var alertTitle: String {
        switch self {
        case .screenRecording:
            return "需要屏幕录制权限"
        case .microphone:
            return "需要麦克风权限"
        case .accessibility:
            return "需要辅助功能权限"
        }
    }
    
    var alertMessage: String {
        switch self {
        case .screenRecording:
            return "为了能够截图和录制屏幕，请在系统偏好设置中允许此应用访问屏幕录制。"
        case .microphone:
            return "为了能够录制音频，请在系统偏好设置中允许此应用访问麦克风。"
        case .accessibility:
            return "为了能够使用快捷键功能，请在系统偏好设置中允许此应用访问辅助功能。"
        }
    }
}