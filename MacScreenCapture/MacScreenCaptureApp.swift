//
//  MacScreenCaptureApp.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/25.
//

import SwiftUI
import Foundation
import AppKit

@available(macOS 13.0, *)
@main
struct MacScreenCaptureApp: App {
    @StateObject private var permissionManager = PermissionManager()
    @StateObject private var captureManager: CaptureManager
    private static var didSetupRuntimeServices = false
    
    init() {
        UserDefaults.registerMacScreenCaptureDefaults()
        let sharedCaptureManager = CaptureManager.shared
        _captureManager = StateObject(wrappedValue: sharedCaptureManager)
        Self.setupRuntimeServices(captureManager: sharedCaptureManager)
    }
    
    var body: some Scene {
        WindowGroup("Mac Screen Capture") {
            ContentView()
                .environmentObject(permissionManager)
                .environmentObject(captureManager)
                .onAppear {
                    refreshApplicationState()
                }
        }
        .windowResizability(.contentSize)
        
        // 菜单栏应用
        MenuBarExtra("Screen Capture", systemImage: "camera.fill") {
            MenuBarView()
                .environmentObject(permissionManager)
                .environmentObject(captureManager)
        }
    }
    
    private static func setupRuntimeServices(captureManager: CaptureManager) {
        guard !didSetupRuntimeServices else { return }
        didSetupRuntimeServices = true

        // 设置默认用户偏好
        setupDefaultUserDefaults()

        // 初始化快捷键管理器
        _ = HotKeyManager.shared

        // 初始化WindowManager
        _ = WindowManager.shared

        // 避免常驻后台后被 App Nap/自动终止影响全局快捷键响应
        BackgroundResponsivenessManager.shared.start()

        // 监听应用退出通知
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            BackgroundResponsivenessManager.shared.stop()
            Task {
                await captureManager.cleanup()
            }
        }
    }

    private func refreshApplicationState() {
        permissionManager.checkAllPermissions()
        captureManager.initialize()
    }

    private static func setupDefaultUserDefaults() {
        let defaults = UserDefaults.standard
        
        // 设置默认值（如果还没有设置）
        if defaults.object(forKey: "autoHideWindowDuringCapture") == nil {
            defaults.set(true, forKey: "autoHideWindowDuringCapture")
        }
        
        if defaults.object(forKey: "autoShowWindowAfterCapture") == nil {
            defaults.set(false, forKey: "autoShowWindowAfterCapture")
        }

        if defaults.object(forKey: "autoSaveScreenshots") == nil {
            defaults.set(true, forKey: "autoSaveScreenshots")
        }

        if defaults.object(forKey: "screenshotFormat") == nil {
            defaults.set("PNG", forKey: "screenshotFormat")
        }
    }
}
