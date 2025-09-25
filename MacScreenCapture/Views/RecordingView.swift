//
//  RecordingView.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/25.
//

import SwiftUI
import ScreenCaptureKit

struct RecordingView: View {
    @EnvironmentObject var captureManager: CaptureManager
    @EnvironmentObject var permissionManager: PermissionManager
    @State private var errorMessage: String?
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 20) {
            // 权限状态检查
            if !permissionManager.hasScreenRecordingPermission {
                PermissionWarningView()
            } else {
                // 录制模式选择
                RecordingModeSelector()
                
                // 显示器/窗口选择
                if captureManager.captureMode == .fullScreen {
                    DisplaySelector()
                } else if captureManager.captureMode == .window {
                    WindowSelector()
                }
                
                // 录制控制区域
                RecordingControlsView()
                
                // 录制状态显示
                if captureManager.isRecording {
                    RecordingStatusView()
                }
            }
            
            Spacer()
        }
        .padding()
        .alert("录制错误", isPresented: .constant(errorMessage != nil)) {
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
    private func RecordingModeSelector() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("录制模式")
                .font(.headline)
            
            Picker("录制模式", selection: $captureManager.captureMode) {
                ForEach([CaptureMode.fullScreen, CaptureMode.window], id: \.self) { mode in
                    HStack {
                        Image(systemName: mode.systemImage)
                        Text(mode.rawValue)
                    }
                    .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(captureManager.isRecording)
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
                .disabled(captureManager.isRecording)
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
                .disabled(captureManager.isRecording)
            }
        }
    }
    
    @ViewBuilder
    private func RecordingControlsView() -> some View {
        VStack(spacing: 16) {
            // 主要控制按钮
            HStack(spacing: 16) {
                // 开始/停止录制按钮
                Button(action: {
                    if captureManager.isRecording {
                        captureManager.stopRecording()
                    } else {
                        startRecording()
                    }
                }) {
                    HStack {
                        Image(systemName: captureManager.isRecording ? "stop.fill" : "record.circle")
                            .foregroundColor(captureManager.isRecording ? .red : .primary)
                        
                        Text(captureManager.isRecording ? "停止录制" : "开始录制")
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!permissionManager.hasScreenRecordingPermission)
                .keyboardShortcut(.init("r"), modifiers: [.command, .shift])
                
                // 暂停/恢复按钮
                if captureManager.isRecording {
                    Button(action: {
                        captureManager.togglePauseRecording()
                    }) {
                        HStack {
                            Image(systemName: captureManager.isPaused ? "play.fill" : "pause.fill")
                            Text(captureManager.isPaused ? "恢复" : "暂停")
                        }
                        .frame(minWidth: 80)
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.space, modifiers: [.command])
                }
            }
            
            // 录制设置按钮
            if !captureManager.isRecording {
                Button("录制设置") {
                    showingSettings = true
                }
                .buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $showingSettings) {
            RecordingSettingsView()
        }
    }
    
    @ViewBuilder
    private func RecordingStatusView() -> some View {
        VStack(spacing: 12) {
            // 录制指示器
            HStack {
                Circle()
                    .fill(captureManager.isPaused ? Color.orange : Color.red)
                    .frame(width: 12, height: 12)
                    .scaleEffect(captureManager.isPaused ? 1.0 : 1.2)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: captureManager.isPaused)
                
                Text(captureManager.isPaused ? "录制已暂停" : "正在录制")
                    .font(.headline)
                    .foregroundColor(captureManager.isPaused ? .orange : .red)
            }
            
            // 录制时长
            Text(formatDuration(captureManager.recordingDuration))
                .font(.title)
                .fontWeight(.bold)
                .fontDesign(.monospaced)
            
            // 录制信息
            VStack(alignment: .leading, spacing: 4) {
                if let url = captureManager.recordingURL {
                    Text("保存位置: \(url.lastPathComponent)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("模式: \(captureManager.captureMode.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func startRecording() {
        errorMessage = nil
        
        Task {
            do {
                try await captureManager.startRecording()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
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

struct RecordingSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var frameRate: Double = 60
    @State private var quality: RecordingQuality = .high
    @State private var includeAudio = true
    @State private var showCursor = true
    
    var body: some View {
        VStack(spacing: 20) {
            Text("录制设置")
                .font(.title2)
                .fontWeight(.semibold)
            
            Form {
                Section("视频设置") {
                    HStack {
                        Text("帧率:")
                        Spacer()
                        Slider(value: $frameRate, in: 15...60, step: 15) {
                            Text("帧率")
                        }
                        Text("\(Int(frameRate)) FPS")
                            .frame(width: 60)
                    }
                    
                    Picker("质量", selection: $quality) {
                        ForEach(RecordingQuality.allCases, id: \.self) { quality in
                            Text(quality.rawValue).tag(quality)
                        }
                    }
                    
                    Toggle("显示鼠标指针", isOn: $showCursor)
                }
                
                Section("音频设置") {
                    Toggle("录制音频", isOn: $includeAudio)
                }
            }
            
            HStack {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("保存") {
                    // TODO: 保存设置
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}

enum RecordingQuality: String, CaseIterable {
    case low = "低"
    case medium = "中"
    case high = "高"
    case ultra = "超高"
}

#Preview {
    RecordingView()
        .environmentObject(CaptureManager())
        .environmentObject(PermissionManager())
        .frame(width: 600, height: 400)
}