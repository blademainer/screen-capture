//
//  KeyboardShortcuts.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/25.
//

import Foundation
import Carbon
import AppKit

/// 全局快捷键管理器
class KeyboardShortcuts: ObservableObject {
    
    // MARK: - Singleton
    static let shared = KeyboardShortcuts()
    
    // MARK: - Properties
    private var hotKeys: [String: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    
    // MARK: - Callbacks
    var onScreenshotFullScreen: (() -> Void)?
    var onScreenshotWindow: (() -> Void)?
    var onScreenshotRegion: (() -> Void)?
    var onStartStopRecording: (() -> Void)?
    var onPauseResumeRecording: (() -> Void)?
    
    // MARK: - Initialization
    private init() {
        setupEventHandler()
        registerDefaultShortcuts()
    }
    
    deinit {
        unregisterAllShortcuts()
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
    
    // MARK: - Public Methods
    
    /// 注册快捷键
    func registerShortcut(
        identifier: String,
        keyCode: UInt32,
        modifiers: UInt32,
        callback: @escaping () -> Void
    ) {
        // 先注销已存在的快捷键
        unregisterShortcut(identifier: identifier)
        
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(identifier.hashValue), id: UInt32(identifier.hashValue))
        
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr, let hotKey = hotKeyRef {
            hotKeys[identifier] = hotKey
            
            // 存储回调
            switch identifier {
            case "screenshot_fullscreen":
                onScreenshotFullScreen = callback
            case "screenshot_window":
                onScreenshotWindow = callback
            case "screenshot_region":
                onScreenshotRegion = callback
            case "recording_toggle":
                onStartStopRecording = callback
            case "recording_pause":
                onPauseResumeRecording = callback
            default:
                break
            }
            
            print("注册快捷键成功: \(identifier)")
        } else {
            print("注册快捷键失败: \(identifier), 状态: \(status)")
        }
    }
    
    /// 注销快捷键
    func unregisterShortcut(identifier: String) {
        if let hotKey = hotKeys[identifier] {
            UnregisterEventHotKey(hotKey)
            hotKeys.removeValue(forKey: identifier)
            print("注销快捷键: \(identifier)")
        }
    }
    
    /// 注销所有快捷键
    func unregisterAllShortcuts() {
        for (identifier, hotKey) in hotKeys {
            UnregisterEventHotKey(hotKey)
            print("注销快捷键: \(identifier)")
        }
        hotKeys.removeAll()
    }
    
    // MARK: - Private Methods
    
    /// 设置事件处理器
    private func setupEventHandler() {
        let eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, theEvent, userData) -> OSStatus in
                return KeyboardShortcuts.shared.handleHotKeyEvent(theEvent)
            },
            1,
            [eventSpec],
            nil,
            &eventHandler
        )
    }
    
    /// 处理热键事件
    private func handleHotKeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event = event else { return eventNotHandledErr }
        
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            OSType(kEventParamDirectObject),
            OSType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        
        guard status == noErr else { return status }
        
        // 根据热键ID执行相应的回调
        DispatchQueue.main.async {
            switch hotKeyID.signature {
            case OSType("screenshot_fullscreen".hashValue):
                self.onScreenshotFullScreen?()
            case OSType("screenshot_window".hashValue):
                self.onScreenshotWindow?()
            case OSType("screenshot_region".hashValue):
                self.onScreenshotRegion?()
            case OSType("recording_toggle".hashValue):
                self.onStartStopRecording?()
            case OSType("recording_pause".hashValue):
                self.onPauseResumeRecording?()
            default:
                break
            }
        }
        
        return noErr
    }
    
    /// 注册默认快捷键
    private func registerDefaultShortcuts() {
        // Cmd+Shift+S: 全屏截图
        registerShortcut(
            identifier: "screenshot_fullscreen",
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(cmdKey | shiftKey)
        ) {
            // 回调将在外部设置
        }
        
        // Cmd+Shift+W: 窗口截图
        registerShortcut(
            identifier: "screenshot_window",
            keyCode: UInt32(kVK_ANSI_W),
            modifiers: UInt32(cmdKey | shiftKey)
        ) {
            // 回调将在外部设置
        }
        
        // Cmd+Shift+A: 区域截图
        registerShortcut(
            identifier: "screenshot_region",
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(cmdKey | shiftKey)
        ) {
            // 回调将在外部设置
        }
        
        // Cmd+Shift+R: 开始/停止录制
        registerShortcut(
            identifier: "recording_toggle",
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: UInt32(cmdKey | shiftKey)
        ) {
            // 回调将在外部设置
        }
        
        // Cmd+Space: 暂停/恢复录制
        registerShortcut(
            identifier: "recording_pause",
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey)
        ) {
            // 回调将在外部设置
        }
    }
}

// MARK: - Key Code Constants
extension KeyboardShortcuts {
    
    /// 常用按键代码
    enum KeyCode: UInt32 {
        case a = 0x00
        case s = 0x01
        case d = 0x02
        case f = 0x03
        case h = 0x04
        case g = 0x05
        case z = 0x06
        case x = 0x07
        case c = 0x08
        case v = 0x09
        case b = 0x0B
        case q = 0x0C
        case w = 0x0D
        case e = 0x0E
        case r = 0x0F
        case y = 0x10
        case t = 0x11
        case one = 0x12
        case two = 0x13
        case three = 0x14
        case four = 0x15
        case six = 0x16
        case five = 0x17
        case equal = 0x18
        case nine = 0x19
        case seven = 0x1A
        case minus = 0x1B
        case eight = 0x1C
        case zero = 0x1D
        case rightBracket = 0x1E
        case o = 0x1F
        case u = 0x20
        case leftBracket = 0x21
        case i = 0x22
        case p = 0x23
        case l = 0x25
        case j = 0x26
        case quote = 0x27
        case k = 0x28
        case semicolon = 0x29
        case backslash = 0x2A
        case comma = 0x2B
        case slash = 0x2C
        case n = 0x2D
        case m = 0x2E
        case period = 0x2F
        case grave = 0x32
        case keypadDecimal = 0x41
        case keypadMultiply = 0x43
        case keypadPlus = 0x45
        case keypadClear = 0x47
        case keypadDivide = 0x4B
        case keypadEnter = 0x4C
        case keypadMinus = 0x4E
        case keypadEquals = 0x51
        case keypad0 = 0x52
        case keypad1 = 0x53
        case keypad2 = 0x54
        case keypad3 = 0x55
        case keypad4 = 0x56
        case keypad5 = 0x57
        case keypad6 = 0x58
        case keypad7 = 0x59
        case keypad8 = 0x5B
        case keypad9 = 0x5C
        case `return` = 0x24
        case tab = 0x30
        case space = 0x31
        case delete = 0x33
        case escape = 0x35
        case command = 0x37
        case shift = 0x38
        case capsLock = 0x39
        case option = 0x3A
        case control = 0x3B
        case rightShift = 0x3C
        case rightOption = 0x3D
        case rightControl = 0x3E
        case function = 0x3F
        case f17 = 0x40
        case volumeUp = 0x48
        case volumeDown = 0x49
        case mute = 0x4A
        case f18 = 0x4F
        case f19 = 0x50
        case f20 = 0x5A
        case f5 = 0x60
        case f6 = 0x61
        case f7 = 0x62
        case f3 = 0x63
        case f8 = 0x64
        case f9 = 0x65
        case f11 = 0x67
        case f13 = 0x69
        case f16 = 0x6A
        case f14 = 0x6B
        case f10 = 0x6D
        case f12 = 0x6F
        case f15 = 0x71
        case help = 0x72
        case home = 0x73
        case pageUp = 0x74
        case forwardDelete = 0x75
        case f4 = 0x76
        case end = 0x77
        case f2 = 0x78
        case pageDown = 0x79
        case f1 = 0x7A
        case leftArrow = 0x7B
        case rightArrow = 0x7C
        case downArrow = 0x7D
        case upArrow = 0x7E
    }
    
    /// 修饰键
    enum Modifier: UInt32 {
        case command = 0x0100
        case shift = 0x0200
        case option = 0x0800
        case control = 0x1000
    }
}