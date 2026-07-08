//
//  ContentView.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/25.
//

import SwiftUI

@available(macOS 12.3, *)
struct ContentView: View {
    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var captureManager: CaptureManager
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ScreenshotView()
                .tabItem {
                    Image(systemName: "camera")
                    Text("截图")
                }
                .tag(0)

            RecordingView()
                .tabItem {
                    Image(systemName: "video")
                    Text("录制")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("设置")
                }
                .tag(2)
        }
        .frame(width: 600, height: 400)
        .background(Color(.windowBackgroundColor))
        .background(
            WindowAccessor { window in
                WindowManager.shared.setMainWindow(window)
            }
            .frame(width: 0, height: 0)
        )
        .onAppear {
            checkPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            selectedTab = 2
        }
    }
    
    private func checkPermissions() {
        if !permissionManager.hasScreenRecordingPermission {
            permissionManager.requestScreenRecordingPermission()
        }
    }
}

#Preview {
    if #available(macOS 12.3, *) {
        ContentView()
            .environmentObject(PermissionManager())
            .environmentObject(CaptureManager())
    } else {
        Text("需要 macOS 12.3 或更高版本")
    }
}
