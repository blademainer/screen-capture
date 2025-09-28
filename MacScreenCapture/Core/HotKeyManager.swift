import Foundation
import Carbon
import Cocoa
import SwiftUI
import Combine

// MARK: - HotKey Configuration
struct HotKeyConfig: Codable, Equatable {
    let keyCode: UInt32?
    let modifiers: UInt32
    let isEnabled: Bool
    let description: String
    
    var displayString: String {
        guard let keyCode = keyCode else {
            return "未设置"
        }
        
        var result = ""
        
        // 修饰键
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        
        // 主键
        result += keyCodeToString(keyCode)
        
        return result
    }
    
    private func keyCodeToString(_ keyCode: UInt32) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 36: return "Return"
        case 48: return "Tab"
        case 76: return "Enter"
        case 117: return "Forward Delete"
        case 115: return "Home"
        case 116: return "Page Up"
        case 119: return "End"
        case 121: return "Page Down"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key\(keyCode)"
        }
    }
}

// MARK: - HotKey Actions
enum HotKeyAction: String, CaseIterable, Codable {
    case fullScreenshot = "full_screenshot"
    case regionScreenshot = "region_screenshot"
    case windowScreenshot = "window_screenshot"
    case startRecording = "start_recording"
    case stopRecording = "stop_recording"
    case scrollScreenshot = "scroll_screenshot"
    
    var defaultConfig: HotKeyConfig {
        switch self {
        case .fullScreenshot:
            return HotKeyConfig(keyCode: 1, modifiers: UInt32(cmdKey | shiftKey), isEnabled: true, description: "全屏截图")
        case .regionScreenshot:
            return HotKeyConfig(keyCode: 2, modifiers: UInt32(cmdKey | shiftKey), isEnabled: true, description: "区域截图")
        case .windowScreenshot:
            return HotKeyConfig(keyCode: 3, modifiers: UInt32(cmdKey | shiftKey), isEnabled: true, description: "窗口截图")
        case .startRecording:
            return HotKeyConfig(keyCode: 15, modifiers: UInt32(cmdKey | shiftKey), isEnabled: true, description: "开始录制")
        case .stopRecording:
            return HotKeyConfig(keyCode: 17, modifiers: UInt32(cmdKey | shiftKey), isEnabled: true, description: "停止录制")
        case .scrollScreenshot:
            return HotKeyConfig(keyCode: 1, modifiers: UInt32(cmdKey | optionKey), isEnabled: true, description: "滚动截图")
        }
    }
    
    var localizedDescription: String {
        switch self {
        case .fullScreenshot: return "全屏截图"
        case .regionScreenshot: return "区域截图"
        case .windowScreenshot: return "窗口截图"
        case .startRecording: return "开始录制"
        case .stopRecording: return "停止录制"
        case .scrollScreenshot: return "滚动截图"
        }
    }
}

// MARK: - HotKey Manager
@available(macOS 12.3, *)
class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()
    
    // 快捷键配置
    @Published var hotKeys: [HotKeyAction: HotKeyConfig] = [:]
    
    // 已注册的快捷键
    private var registeredHotKeys: [HotKeyAction: EventHotKeyRef] = [:]
    
    // 事件处理器
    private var eventHandler: EventHandlerRef?
    
    // 配置文件路径
    private let configURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("MacScreenCapture")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("hotkeys.json")
    }()
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        loadConfiguration()
        setupDefaultHotKeys()
        registerEventHandler()
    }
    
    deinit {
        unregisterAllHotKeys()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }
    
    // MARK: - Configuration Management
    private func setupDefaultHotKeys() {
        for action in HotKeyAction.allCases {
            if hotKeys[action] == nil {
                hotKeys[action] = action.defaultConfig
            }
        }
        saveConfiguration()
    }
    
    private func loadConfiguration() {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            hotKeys = try decoder.decode([HotKeyAction: HotKeyConfig].self, from: data)
        } catch {
            print("Failed to load hotkey configuration: \(error)")
        }
    }
    
    private func saveConfiguration() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(hotKeys)
            try data.write(to: configURL)
        } catch {
            print("Failed to save hotkey configuration: \(error)")
        }
    }
    
    // MARK: - Event Handler Setup
    private func registerEventHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        
        let callback: EventHandlerProcPtr = { (nextHandler, theEvent, userData) -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            return manager.handleHotKeyEvent(theEvent)
        }
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        
        if status != noErr {
            print("Failed to install event handler: \(status)")
        }
    }
    
    private func handleHotKeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event = event else { return OSStatus(eventNotHandledErr) }
        
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        
        guard status == noErr else { return status }
        
        // 执行对应的快捷键操作
        executeHotKeyAction(hotKeyID)
        
        return noErr
    }
    
    private func executeHotKeyAction(_ hotKeyID: EventHotKeyID) {
        // 根据 hotKeyID 找到对应的 action
        for (action, _) in registeredHotKeys {
            let actionSignature = generateSignature(for: action)
            let actionID = EventHotKeyID(
                signature: OSType(actionSignature),
                id: UInt32(actionSignature)
            )
            
            if hotKeyID.signature == actionID.signature && hotKeyID.id == actionID.id {
                DispatchQueue.main.async {
                    self.performAction(action)
                }
                break
            }
        }
    }
    
    private func performAction(_ action: HotKeyAction) {
        Task { @MainActor in
            let captureManager = CaptureManager.shared
            
            switch action {
            case .fullScreenshot:
                await captureManager.captureFullScreen()
            case .regionScreenshot:
                await captureManager.captureRegion()
            case .windowScreenshot:
                await captureManager.captureWindow()
            case .startRecording:
                if !captureManager.isRecording {
                    do {
                        try await captureManager.startRecording()
                    } catch {
                        print("开始录制失败: \(error)")
                    }
                }
            case .stopRecording:
                if captureManager.isRecording {
                    await captureManager.stopRecording()
                }
            case .scrollScreenshot:
                await captureManager.captureScrollingWindow()
            }
        }
    }
    
    // MARK: - HotKey Registration
    func registerHotKey(_ action: HotKeyAction, config: HotKeyConfig) -> Bool {
        // 检查配置是否有效
        guard let keyCode = config.keyCode, keyCode > 0 else {
            print("Invalid or missing keyCode for action \(action)")
            // 保存配置但不注册快捷键
            hotKeys[action] = config
            saveConfiguration()
            return false
        }
        
        // 检查快捷键是否已被占用
        if isHotKeyConflict(config, excluding: action) {
            showConflictAlert(for: action)
            return false
        }
        
        // 注销旧的快捷键
        unregisterHotKey(action)
        
        guard config.isEnabled else {
            hotKeys[action] = config
            saveConfiguration()
            return true
        }
        
        // 注册新的快捷键
        var hotKeyRef: EventHotKeyRef?
        let signature = generateSignature(for: action)
        let hotKeyID = EventHotKeyID(
            signature: OSType(signature),
            id: UInt32(signature)
        )
        
        let status = RegisterEventHotKey(
            keyCode,
            config.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        guard status == noErr, let hotKey = hotKeyRef else {
            print("Failed to register hotkey for \(action): \(status)")
            return false
        }
        
        // 保存注册信息
        registeredHotKeys[action] = hotKey
        hotKeys[action] = config
        
        // 持久化配置
        saveConfiguration()
        
        return true
    }
    
    private func unregisterHotKey(_ action: HotKeyAction) {
        if let hotKeyRef = registeredHotKeys[action] {
            UnregisterEventHotKey(hotKeyRef)
            registeredHotKeys.removeValue(forKey: action)
        }
    }
    
    private func unregisterAllHotKeys() {
        for action in registeredHotKeys.keys {
            unregisterHotKey(action)
        }
    }
    
    // MARK: - Conflict Detection
    private func isHotKeyConflict(_ config: HotKeyConfig, excluding: HotKeyAction? = nil) -> Bool {
        guard let keyCode = config.keyCode else { return false }
        
        for (action, existingConfig) in hotKeys {
            if let excluding = excluding, action == excluding { continue }
            if existingConfig.isEnabled,
               let existingKeyCode = existingConfig.keyCode,
               existingKeyCode == keyCode &&
               existingConfig.modifiers == config.modifiers {
                return true
            }
        }
        return false
    }
    
    private func showConflictAlert(for action: HotKeyAction) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "快捷键冲突"
            alert.informativeText = "该快捷键已被其他功能使用，请选择不同的快捷键组合。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
    
    // MARK: - Public Methods
    func registerAllHotKeys() {
        for (action, config) in hotKeys {
            _ = registerHotKey(action, config: config)
        }
    }
    
    func updateHotKey(_ action: HotKeyAction, config: HotKeyConfig) {
        _ = registerHotKey(action, config: config)
        objectWillChange.send()
    }
    
    // MARK: - Helper Methods
    private func generateSignature(for action: HotKeyAction) -> UInt32 {
        // 使用action的rawValue生成稳定的签名
        let rawValue = action.rawValue
        var hasher = Hasher()
        hasher.combine(rawValue)
        let hash = hasher.finalize()
        // 安全地转换为 UInt32，避免溢出
        let safeHash = UInt32(truncatingIfNeeded: abs(hash))
        return safeHash & 0x7FFFFFFF
    }
    
    private func generateSignature(for config: HotKeyConfig) -> String {
        // 安全处理：如果 keyCode 为 nil，返回默认签名
        let keyCode = config.keyCode ?? 0
        let modifierValue = config.modifiers
        return "\(keyCode)_\(modifierValue)"
    }
}

// MARK: - String Extension
extension String {
    var fourCharCode: FourCharCode {
        let chars = Array(self.prefix(4).padding(toLength: 4, withPad: " ", startingAt: 0))
        return chars.reduce(0) { result, char in
            (result << 8) + FourCharCode(char.asciiValue ?? 0)
        }
    }
}