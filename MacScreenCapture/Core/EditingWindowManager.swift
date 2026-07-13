import Foundation
import SwiftUI
import Cocoa

// MARK: - Editing Window Manager
class EditingWindowManager: ObservableObject {
    static let shared = EditingWindowManager()
    
    @Published var activeWindows: [EditingWindowController] = []
    
    private init() {}
    
    // MARK: - Window Management
    func openEditingWindow(for image: NSImage, at _: CGPoint? = nil) {
        DispatchQueue.main.async { [weak self] in
            let editingWindow = EditingWindowController(screenshot: image)

            editingWindow.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            editingWindow.window?.makeKeyAndOrderFront(nil)
            editingWindow.window?.orderFrontRegardless()
            
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

    private func removeWindow(_ controller: EditingWindowController) {
        activeWindows.removeAll { $0 === controller }
    }
    
    private func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        
        SystemNotificationPresenter.deliverLegacy(message: "截图已自动复制到剪贴板")
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
