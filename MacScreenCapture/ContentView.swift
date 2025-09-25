//
//  ContentView.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var captureManager: CaptureManager
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏
            HeaderView()
            
            // 主要内容区域
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
        }
        .background(Color(.windowBackgroundColor))
        .onAppear {
            checkPermissions()
        }
    }
    
    private func checkPermissions() {
        if !permissionManager.hasScreenRecordingPermission {
            permissionManager.requestScreenRecordingPermission()
        }
    }
}

struct HeaderView: View {
    var body: some View {
        HStack {
            Image(systemName: "camera.fill")
                .foregroundColor(.blue)
                .font(.title2)
            
            Text("Mac Screen Capture")
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
    }
}

#Preview {
    ContentView()
        .environmentObject(PermissionManager())
        .environmentObject(CaptureManager())
}