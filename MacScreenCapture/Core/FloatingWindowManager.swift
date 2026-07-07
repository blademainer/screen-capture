import Foundation
import SwiftUI
import Cocoa

// MARK: - Floating Window Manager
class FloatingWindowManager: ObservableObject {
    static let shared = FloatingWindowManager()
    
    @Published var activeWindows: [FloatingWindowController] = []
    
    private init() {}
    
    // MARK: - Window Management
    func showFloatingPreview(for image: NSImage, at position: CGPoint? = nil) {
        DispatchQueue.main.async { [weak self] in
            let floatingWindow = FloatingWindowController(screenshot: image)
            
            // 设置窗口位置
            if let position = position {
                floatingWindow.window?.setFrameOrigin(position)
            } else {
                // 智能定位：避免与现有浮窗重叠
                self?.positionNewWindow(floatingWindow.window)
            }
            
            floatingWindow.showWindow(nil)
            floatingWindow.window?.makeKeyAndOrderFront(nil)
            
            // 添加到活动窗口列表
            self?.activeWindows.append(floatingWindow)
            
            // 设置窗口关闭回调
            floatingWindow.onWindowClose = { [weak self] controller in
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

        guard let screen = NSScreen.main else {
            window.center()
            return
        }

        let origin = FloatingWindowLayout.origin(
            for: window.frame.size,
            existingWindowFrames: activeWindows.compactMap { $0.window?.frame },
            visibleFrame: screen.visibleFrame
        )
        window.setFrameOrigin(origin)
    }
    
    private func removeWindow(_ controller: FloatingWindowController) {
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
}
