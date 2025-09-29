import Foundation
import SwiftUI
import Cocoa

// MARK: - Editing Window Manager
class EditingWindowManager: ObservableObject {
    static let shared = EditingWindowManager()
    
    @Published var activeWindows: [EditingWindowController] = []
    
    private init() {}
    
    // MARK: - Window Management
    func openEditingWindow(for image: NSImage, at position: CGPoint? = nil) {
        DispatchQueue.main.async { [weak self] in
            let editingWindow = EditingWindowController(screenshot: image)
            
            // 设置窗口位置
            if let position = position {
                editingWindow.window?.setFrameOrigin(position)
            } else {
                // 智能定位：避免与现有窗口重叠
                self?.positionNewWindow(editingWindow.window)
            }
            
            editingWindow.showWindow(nil)
            editingWindow.window?.makeKeyAndOrderFront(nil)
            
            // 添加到活动窗口列表
            self?.activeWindows.append(editingWindow)
            
            // 设置窗口关闭回调
            editingWindow.onWindowClose = { [weak self] controller in
                self?.removeWindow(controller)
            }
            
            // 自动复制到剪贴板（如果启用）
            if UserDefaults.standard.bool(forKey: "autoCopyToClipboard") {
                self?.copyToClipboard(image)
            }
        }
    }
    
    private func positionNewWindow(_ window: NSWindow?) {
        guard let window = window else { return }
        
        if activeWindows.isEmpty {
            // 第一个窗口居中显示
            window.center()
        } else {
            // 后续窗口错开显示
            let offset: CGFloat = 40
            let baseFrame = activeWindows.first?.window?.frame ?? window.frame
            let newOrigin = CGPoint(
                x: baseFrame.origin.x + offset * CGFloat(activeWindows.count),
                y: baseFrame.origin.y - offset * CGFloat(activeWindows.count)
            )
            window.setFrameOrigin(newOrigin)
            
            // 确保窗口在屏幕范围内
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                var frame = window.frame
                
                if frame.maxX > screenFrame.maxX {
                    frame.origin.x = screenFrame.maxX - frame.width
                }
                if frame.minY < screenFrame.minY {
                    frame.origin.y = screenFrame.minY
                }
                
                window.setFrame(frame, display: true)
            }
        }
    }
    
    private func removeWindow(_ controller: EditingWindowController) {
        activeWindows.removeAll { $0 === controller }
    }
    
    private func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        
        // 显示通知
        let notification = NSUserNotification()
        notification.title = "MacScreenCapture"
        notification.informativeText = "截图已自动复制到剪贴板"
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    // MARK: - Batch Operations
    func closeAllWindows() {
        for controller in activeWindows {
            controller.close()
        }
        activeWindows.removeAll()
    }
    
    func minimizeAllWindows() {
        for controller in activeWindows {
            controller.window?.miniaturize(nil)
        }
    }
    
    func restoreAllWindows() {
        for controller in activeWindows {
            if controller.window?.isMiniaturized == true {
                controller.window?.deminiaturize(nil)
            }
        }
    }
    
    // MARK: - Window State
    var hasActiveWindows: Bool {
        return !activeWindows.isEmpty
    }
    
    var activeWindowCount: Int {
        return activeWindows.count
    }
}