//
//  ScreenshotView.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/25.
//

import SwiftUI
import ScreenCaptureKit

@available(macOS 12.3, *)
struct ScreenshotView: View {
    @EnvironmentObject var captureManager: CaptureManager
    @EnvironmentObject var permissionManager: PermissionManager
    @State private var isCapturing = false
    @State private var showingPreview = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            // 权限状态检查
            if !permissionManager.hasScreenRecordingPermission {
                PermissionWarningView()
            } else {
                // 截图模式选择
                CaptureModeSelector()
                
                // 显示器/窗口选择
                if captureManager.captureMode == .fullScreen {
                    DisplaySelector()
                } else if captureManager.captureMode == .window {
                    WindowSelector()
                }
                
                // 截图按钮
                CaptureButton()
                
                // 预览区域
                if let image = captureManager.lastCapturedImage {
                    PreviewSection(image: image)
                }
            }
            
            Spacer()
        }
        .padding()
        .alert("截图错误", isPresented: .constant(errorMessage != nil)) {
            Button("确定") {
                errorMessage = nil
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .onAppear {
            Task {
                await captureManager.updateAvailableContent()
            }
        }
    }
    
    @ViewBuilder
    private func PermissionWarningView() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("需要屏幕录制权限")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("请在系统偏好设置中允许此应用访问屏幕录制功能")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button("打开系统偏好设置") {
                permissionManager.requestScreenRecordingPermission()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func CaptureModeSelector() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("截图模式")
                .font(.headline)
            
            Picker("截图模式", selection: $captureManager.captureMode) {
                ForEach(CaptureMode.allCases, id: \.self) { mode in
                    HStack {
                        Image(systemName: mode.systemImage)
                        Text(mode.rawValue)
                    }
                    .tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    @ViewBuilder
    private func DisplaySelector() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择显示器")
                .font(.headline)
            
            if captureManager.availableDisplays.isEmpty {
                Text("没有可用的显示器")
                    .foregroundColor(.secondary)
            } else {
                Picker("显示器", selection: $captureManager.selectedDisplay) {
                    ForEach(captureManager.availableDisplays, id: \.displayID) { display in
                        Text("显示器 \(display.displayID) (\(Int(display.frame.width))×\(Int(display.frame.height)))")
                            .tag(display as SCDisplay?)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
    
    @ViewBuilder
    private func WindowSelector() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择窗口")
                .font(.headline)
            
            if captureManager.availableWindows.isEmpty {
                Text("没有可用的窗口")
                    .foregroundColor(.secondary)
            } else {
                Picker("窗口", selection: $captureManager.selectedWindow) {
                    Text("请选择窗口").tag(nil as SCWindow?)
                    
                    ForEach(captureManager.availableWindows, id: \.windowID) { window in
                        Text(window.title ?? "未知窗口")
                            .tag(window as SCWindow?)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
    
    @ViewBuilder
    private func CaptureButton() -> some View {
        Button(action: {
            captureScreenshot()
        }) {
            HStack {
                if isCapturing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "camera.fill")
                }
                
                Text(isCapturing ? "截图中..." : "开始截图")
            }
            .frame(minWidth: 120)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isCapturing || !permissionManager.hasScreenRecordingPermission)
        .keyboardShortcut(.init("s"), modifiers: [.command, .shift])
    }
    
    @ViewBuilder
    private func PreviewSection(image: NSImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("预览")
                .font(.headline)
            
            HStack {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 200, maxHeight: 150)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("尺寸: \(Int(image.size.width)) × \(Int(image.size.height))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button("在Finder中显示") {
                            // TODO: 实现在Finder中显示功能
                        }
                        .buttonStyle(.bordered)
                        
                        Button("复制到剪贴板") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setData(image.tiffRepresentation, forType: .tiff)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                Spacer()
            }
        }
    }
    
    private func captureScreenshot() {
        guard !isCapturing else { return }
        
        isCapturing = true
        errorMessage = nil
        
        Task {
            do {
                _ = try await captureManager.captureScreenshot()
                await MainActor.run {
                    isCapturing = false
                    showingPreview = true
                }
            } catch {
                await MainActor.run {
                    isCapturing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    if #available(macOS 12.3, *) {
        ScreenshotView()
            .environmentObject(CaptureManager())
            .environmentObject(PermissionManager())
            .frame(width: 600, height: 400)
    } else {
        Text("需要 macOS 12.3 或更高版本")
    }
}