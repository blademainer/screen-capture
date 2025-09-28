import SwiftUI
import Carbon

@available(macOS 12.3, *)
struct HotKeySettingsView: View {
    @StateObject private var hotKeyManager = HotKeyManager.shared
    @State private var isRecording: HotKeyAction? = nil
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 标题
            HStack {
                Image(systemName: "keyboard")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("快捷键设置")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("重置默认") {
                    resetToDefaults()
                }
                .buttonStyle(.bordered)
            }
            
            // 说明文字
            Text("点击快捷键按钮，然后按下您想要设置的快捷键组合")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
            
            // 快捷键列表
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(HotKeyAction.allCases, id: \.self) { action in
                        HotKeyRow(
                            action: action,
                            config: hotKeyManager.hotKeys[action] ?? action.defaultConfig,
                            isRecording: isRecording == action,
                            onStartRecording: { 
                                startRecording(action) 
                            },
                            onStopRecording: { 
                                stopRecording() 
                            },
                            onConfigChanged: { config in
                                updateHotKey(action, config: config)
                            },
                            onToggleEnabled: { isEnabled in
                                toggleHotKey(action, enabled: isEnabled)
                            }
                        )
                    }
                }
                .padding(.vertical, 8)
            }
            
            Spacer()
            
            // 底部说明
            VStack(alignment: .leading, spacing: 8) {
                Text("提示：")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Text("• 快捷键将在应用后台运行时也能响应")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("• 如果快捷键冲突，系统会自动提示")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("• 可以随时禁用不需要的快捷键")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .alert("提示", isPresented: $showingAlert) {
            Button("确定") { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            // 确保所有快捷键都已注册
            hotKeyManager.registerAllHotKeys()
        }
    }
    
    private func startRecording(_ action: HotKeyAction) {
        isRecording = action
    }
    
    private func stopRecording() {
        isRecording = nil
    }
    
    private func updateHotKey(_ action: HotKeyAction, config: HotKeyConfig) {
        let success = hotKeyManager.registerHotKey(action, config: config)
        if !success {
            alertMessage = "快捷键设置失败，可能与其他应用冲突"
            showingAlert = true
        }
    }
    
    private func toggleHotKey(_ action: HotKeyAction, enabled: Bool) {
        guard var config = hotKeyManager.hotKeys[action] else { return }
        
        let newConfig = HotKeyConfig(
            keyCode: config.keyCode,
            modifiers: config.modifiers,
            isEnabled: enabled,
            description: config.description
        )
        
        hotKeyManager.updateHotKey(action, config: newConfig)
    }
    
    private func resetToDefaults() {
        for action in HotKeyAction.allCases {
            hotKeyManager.updateHotKey(action, config: action.defaultConfig)
        }
        
        alertMessage = "已重置为默认快捷键设置"
        showingAlert = true
    }
}

struct HotKeyRow: View {
    let action: HotKeyAction
    let config: HotKeyConfig
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onConfigChanged: (HotKeyConfig) -> Void
    let onToggleEnabled: (Bool) -> Void
    
    @State private var keyMonitor: Any?
    
    var body: some View {
        HStack(spacing: 16) {
            // 功能图标和名称
            HStack(spacing: 12) {
                Image(systemName: iconForAction(action))
                    .foregroundColor(config.isEnabled ? .blue : .gray)
                    .font(.title3)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.localizedDescription)
                        .font(.body)
                        .foregroundColor(config.isEnabled ? .primary : .secondary)
                    
                    if !config.isEnabled {
                        Text("已禁用")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .frame(width: 140, alignment: .leading)
            
            // 快捷键按钮
            Button(action: isRecording ? onStopRecording : onStartRecording) {
                HStack(spacing: 8) {
                    if isRecording {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .scaleEffect(1.0)
                                .animation(.easeInOut(duration: 0.8).repeatForever(), value: isRecording)
                            
                            Text("按下快捷键...")
                                .foregroundColor(.orange)
                        }
                    } else {
                        Text(config.displayString.isEmpty ? "未设置" : config.displayString)
                            .foregroundColor(config.isEnabled ? .primary : .secondary)
                    }
                }
                .frame(minWidth: 120)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .disabled(!config.isEnabled && !isRecording)
            
            // 启用开关
            Toggle("", isOn: Binding(
                get: { config.isEnabled },
                set: { onToggleEnabled($0) }
            ))
            .toggleStyle(.switch)
            .scaleEffect(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isRecording ? Color.blue.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isRecording ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .onAppear {
            if isRecording {
                startKeyMonitoring()
            }
        }
        .onDisappear {
            stopKeyMonitoring()
        }
        .onChange(of: isRecording) { recording in
            if recording {
                startKeyMonitoring()
            } else {
                stopKeyMonitoring()
            }
        }
    }
    
    private func iconForAction(_ action: HotKeyAction) -> String {
        switch action {
        case .fullScreenshot: return "rectangle.dashed"
        case .regionScreenshot: return "rectangle.dashed.badge.record"
        case .windowScreenshot: return "macwindow"
        case .startRecording: return "record.circle"
        case .stopRecording: return "stop.circle"
        case .scrollScreenshot: return "scroll"
        }
    }
    
    private func startKeyMonitoring() {
        stopKeyMonitoring()
        
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard isRecording else { return event }
            
            let keyCode = UInt32(event.keyCode)
            let modifiers = event.modifierFlags.carbonFlags
            
            // 忽略单独的修饰键
            if isModifierKey(keyCode) {
                return nil
            }
            
            // 创建新的配置
            let newConfig = HotKeyConfig(
                keyCode: keyCode,
                modifiers: modifiers,
                isEnabled: config.isEnabled,
                description: config.description
            )
            
            onConfigChanged(newConfig)
            onStopRecording()
            
            return nil
        }
    }
    
    private func stopKeyMonitoring() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
    
    private func isModifierKey(_ keyCode: UInt32) -> Bool {
        let modifierKeyCodes: [UInt32] = [54, 55, 56, 57, 58, 59, 60, 61, 62] // Cmd, Shift, Option, Control等
        return modifierKeyCodes.contains(keyCode)
    }
}

// MARK: - NSEvent.ModifierFlags Extension
extension NSEvent.ModifierFlags {
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        
        return flags
    }
}

#Preview {
    if #available(macOS 12.3, *) {
        HotKeySettingsView()
            .frame(width: 600, height: 500)
    } else {
        Text("需要 macOS 12.3 或更高版本")
    }
}