//
//  RecordingView.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/25.
//

import SwiftUI
import ScreenCaptureKit

@available(macOS 12.3, *)
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
                ForEach([CaptureMode.fullScreen, CaptureMode.window, CaptureMode.region], id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.systemImage)
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
                        Task {
                            await captureManager.stopRecording()
                        }
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
                .keyboardShortcut(.init("w"), modifiers: [.option])

                if !captureManager.isRecording {
                    Button(action: {
                        startAudioRecording()
                    }) {
                        HStack {
                            Image(systemName: "waveform.circle")
                            Text("开始录音")
                        }
                        .frame(minWidth: 110)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!permissionManager.hasScreenRecordingPermission)
                    .keyboardShortcut(.init("m"), modifiers: [.command, .shift])
                }

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

                Text(statusTitle)
                    .font(.headline)
                    .foregroundColor(captureManager.isPaused ? .orange : .red)
            }

            // 录制时长
            Text(formatDuration(captureManager.recordingDuration))
                .font(.title)
                .bold()

            // 录制信息
            VStack(alignment: .leading, spacing: 4) {
                if let url = captureManager.recordingURL {
                    Text("保存位置: \(url.lastPathComponent)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("模式: \(captureManager.isAudioOnlyRecording ? "仅录音" : captureManager.captureMode.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // 音频录制状态
                HStack(spacing: 8) {
                    let includeSystemAudio = UserDefaults.standard.bool(forKey: "includeSystemAudio")
                    let includeMicrophone = UserDefaults.standard.bool(forKey: "includeMicrophone")

                    if includeSystemAudio {
                        HStack(spacing: 2) {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundColor(.blue)
                            Text("系统音频")
                        }
                        .font(.caption)
                    }

                    if includeMicrophone {
                        HStack(spacing: 2) {
                            Image(systemName: permissionManager.hasMicrophonePermission ? "mic.fill" : "mic.slash.fill")
                                .foregroundColor(permissionManager.hasMicrophonePermission ? .green : .red)
                            Text("麦克风")
                        }
                        .font(.caption)
                    }

                    if !includeSystemAudio && !includeMicrophone {
                        HStack(spacing: 2) {
                            Image(systemName: "speaker.slash.fill")
                                .foregroundColor(.gray)
                            Text("静音录制")
                        }
                        .font(.caption)
                    }
                }
                .foregroundColor(.secondary)
            }

            // 在Finder中显示按钮（录制完成后显示）
            if !captureManager.isRecording && captureManager.recordingURL != nil {
                Button("在Finder中显示") {
                    showRecordingInFinder()
                }
                .buttonStyle(.bordered)
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
                _ = try await captureManager.startRecordingWithPreflight()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func startAudioRecording() {
        errorMessage = nil

        Task {
            do {
                _ = try await captureManager.startAudioRecordingWithPreflight()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private var statusTitle: String {
        if captureManager.isPaused {
            return captureManager.isAudioOnlyRecording ? "录音已暂停" : "录制已暂停"
        }
        return captureManager.isAudioOnlyRecording ? "正在录音" : "正在录制"
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

    private func showRecordingInFinder() {
        guard let fileURL = captureManager.recordingURL else { return }
        NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
    }
}

struct RecordingSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var permissionManager: PermissionManager
    @State private var frameRate: Double = 60
    @State private var quality: RecordingQuality = .high
    @State private var includeSystemAudio = true
    @State private var includeMicrophone = true
    @State private var showCursor = true
    @State private var startDelaySeconds = 0
    @State private var fileFormat = "MOV"

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

                    Stepper("开录延时: \(startDelaySeconds) 秒", value: $startDelaySeconds, in: 0...30)

                    Picker("导出格式", selection: $fileFormat) {
                        Text("MOV").tag("MOV")
                        Text("MP4").tag("MP4")
                    }

                    Toggle("显示鼠标指针", isOn: $showCursor)
                }

                Section("音频设置") {
                    Toggle("录制系统音频", isOn: $includeSystemAudio)

                    HStack {
                        Toggle("录制麦克风", isOn: $includeMicrophone)

                        if !permissionManager.hasMicrophonePermission {
                            Button("授权") {
                                permissionManager.requestMicrophonePermission()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }

                    if includeMicrophone && !permissionManager.hasMicrophonePermission {
                        Text("需要麦克风权限才能录制音频")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            HStack {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("保存") {
                    // 保存设置到 UserDefaults
                    UserDefaults.standard.set(frameRate, forKey: "recordingFrameRate")
                    UserDefaults.standard.set(quality.rawValue, forKey: "recordingQuality")
                    UserDefaults.standard.set(includeSystemAudio, forKey: "includeSystemAudio")
                    UserDefaults.standard.set(includeMicrophone, forKey: "includeMicrophone")
                    UserDefaults.standard.set(showCursor, forKey: "showCursor")
                    UserDefaults.standard.set(startDelaySeconds, forKey: "recordingStartDelaySeconds")
                    UserDefaults.standard.set(fileFormat, forKey: "recordingFileFormat")

                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 450, height: 350)
        .onAppear {
            // 加载保存的设置
            frameRate = UserDefaults.standard.double(forKey: "recordingFrameRate")
            if frameRate == 0 { frameRate = 60 }

            if let qualityString = UserDefaults.standard.string(forKey: "recordingQuality"),
               let savedQuality = RecordingQuality(rawValue: qualityString) {
                quality = savedQuality
            }

            includeSystemAudio = UserDefaults.standard.bool(forKey: "includeSystemAudio")
            includeMicrophone = UserDefaults.standard.bool(forKey: "includeMicrophone")
            showCursor = UserDefaults.standard.bool(forKey: "showCursor")
            startDelaySeconds = UserDefaults.standard.integer(forKey: "recordingStartDelaySeconds")
            fileFormat = UserDefaults.standard.string(forKey: "recordingFileFormat") ?? "MOV"
        }
    }
}

enum RecordingQuality: String, CaseIterable {
    case low = "低"
    case medium = "中"
    case high = "高"
    case ultra = "超高"
}

#Preview {
    if #available(macOS 12.3, *) {
        RecordingView()
            .environmentObject(CaptureManager())
            .environmentObject(PermissionManager())
            .frame(width: 600, height: 400)
    } else {
        Text("需要 macOS 12.3 或更高版本")
    }
}
