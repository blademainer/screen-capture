//
//  MacScreenCaptureApp.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/25.
//

import SwiftUI

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
        // 应用启动时的初始化设置
        permissionManager.checkAllPermissions()
        captureManager.initialize()
    }
}