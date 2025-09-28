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
    @StateObject private var captureManager = CaptureManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(permissionManager)
                .environmentObject(captureManager)
                .onAppear {
                    setupApplication()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                    // 当窗口成为关键窗口时，设置主窗口引用到WindowManager
                    if let window = notification.object as? NSWindow {
                        if #available(macOS 12.3, *) {
                            WindowManager.shared.setMainWindow(window)
                        }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        // 菜单栏应用
        MenuBarExtra("Screen Capture", systemImage: "camera.fill") {
            MenuBarView()
                .environmentObject(permissionManager)
                .environmentObject(captureManager)
        }
    }
    
    private func setupApplication() {
        // 设置默认用户偏好
        setupDefaultUserDefaults()
        
        // 应用启动时的初始化设置
        permissionManager.checkAllPermissions()
        captureManager.initialize()
        
        // 初始化快捷键管理器
        _ = HotKeyManager.shared
        
        // 初始化WindowManager
        _ = WindowManager.shared
        
        // 监听应用退出通知
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await captureManager.cleanup()
            }
        }
    }
    
    private func setupDefaultUserDefaults() {
        let defaults = UserDefaults.standard
        
        // 设置默认值（如果还没有设置）
        if defaults.object(forKey: "autoHideWindowDuringCapture") == nil {
            defaults.set(true, forKey: "autoHideWindowDuringCapture")
        }
        
        if defaults.object(forKey: "autoShowWindowAfterCapture") == nil {
            defaults.set(false, forKey: "autoShowWindowAfterCapture")
        }
        
        if defaults.object(forKey: "screenshotFormat") == nil {
            defaults.set("PNG", forKey: "screenshotFormat")
        }
    }
}