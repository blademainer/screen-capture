import Foundation
import SwiftUI
import Cocoa

// MARK: - Editing Window Controller
class EditingWindowController: NSWindowController {
    private var screenshot: NSImage
    private var editingSession: ImageEditingSession
    var onWindowClose: ((EditingWindowController) -> Void)?
    
    init(screenshot: NSImage) {
        self.screenshot = screenshot
        self.editingSession = ImageEditingSession(originalImage: screenshot)
        
        // 计算窗口尺寸
        let imageSize = screenshot.size
        let maxSize = CGSize(width: 900, height: 700)
        let aspectRatio = imageSize.width / imageSize.height
        
        var windowSize = imageSize
        if windowSize.width > maxSize.width {
            windowSize.width = maxSize.width
            windowSize.height = windowSize.width / aspectRatio
        }
        if windowSize.height > maxSize.height {
            windowSize.height = maxSize.height
            windowSize.width = windowSize.height * aspectRatio
        }
        
        // 添加工具栏和操作栏的高度
        windowSize.height += 140
        windowSize.width = max(windowSize.width, 500) // 最小宽度
        
        // 创建标准窗口（非浮窗）
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        setupWindow()
        setupContent()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupWindow() {
        guard let window = window else { return }
        
        // 窗口属性设置 - 标准窗口，不置顶
        window.title = "图片编辑"
        window.level = .normal  // 标准窗口级别，不置顶
        window.backgroundColor = NSColor.windowBackgroundColor
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        
        // 设置窗口样式为标准文档窗口
        window.hasShadow = true
        window.isOpaque = true
        
        // 居中显示
        window.center()
        
        // 设置最小尺寸
        window.minSize = NSSize(width: 500, height: 400)
        
        // 窗口动画
        window.animationBehavior = .documentWindow
        
        // 窗口关闭时的处理
        window.delegate = self
        
        // 标准窗口行为
        window.collectionBehavior = [.managed, .participatesInCycle]
        
        // 添加窗口出现动画
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }
    }
    
    private func setupContent() {
        let contentView = EditingWindowContentView(
            screenshot: screenshot,
            editingSession: editingSession,
            onSave: { [weak self] editedImage in
                self?.saveImage(editedImage)
            },
            onCopy: { [weak self] editedImage in
                self?.copyToClipboard(editedImage)
            },
            onShare: { [weak self] editedImage in
                self?.shareImage(editedImage)
            },
            onClose: { [weak self] in
                self?.close()
            }
        )
        
        window?.contentView = NSHostingView(rootView: contentView)
    }
    
    // MARK: - Actions
    private func saveImage(_ image: NSImage) {
        DispatchQueue.main.async { [weak self] in
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.png, .jpeg, .tiff]
            savePanel.nameFieldStringValue = "Screenshot_\(Int(Date().timeIntervalSince1970)).png"
            savePanel.canCreateDirectories = true
            savePanel.isExtensionHidden = false
            
            // 设置默认保存位置到桌面
            if let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
                savePanel.directoryURL = desktopURL
            }
            
            savePanel.begin { [weak self] result in
                if result == .OK, let url = savePanel.url {
                    self?.writeImage(image, to: url)
                }
            }
        }
    }
    
    private func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        
        // 显示复制成功提示
        showNotification("已复制到剪贴板")
    }
    
    private func shareImage(_ image: NSImage) {
        guard let window = window else { return }
        
        let sharingService = NSSharingServicePicker(items: [image])
        sharingService.show(relativeTo: .zero, of: window.contentView!, preferredEdge: .minY)
    }
    
    private func writeImage(_ image: NSImage, to url: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                guard let tiffData = image.tiffRepresentation else {
                    DispatchQueue.main.async {
                        self.showNotification("保存失败：无法获取图片数据")
                    }
                    return
                }
                
                guard let bitmapRep = NSBitmapImageRep(data: tiffData) else {
                    DispatchQueue.main.async {
                        self.showNotification("保存失败：无法处理图片格式")
                    }
                    return
                }
                
                let fileType: NSBitmapImageRep.FileType
                let properties: [NSBitmapImageRep.PropertyKey: Any]
                
                switch url.pathExtension.lowercased() {
                case "jpg", "jpeg":
                    fileType = .jpeg
                    properties = [.compressionFactor: 0.9]
                case "tiff", "tif":
                    fileType = .tiff
                    properties = [:]
                default:
                    fileType = .png
                    properties = [:]
                }
                
                guard let data = bitmapRep.representation(using: fileType, properties: properties) else {
                    DispatchQueue.main.async {
                        self.showNotification("保存失败：无法生成文件数据")
                    }
                    return
                }
                
                let directory = url.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
                }
                
                try data.write(to: url)
                
                DispatchQueue.main.async {
                    self.showNotification("保存成功：\(url.lastPathComponent)")
                    
                    if UserDefaults.standard.bool(forKey: "showInFinderAfterSave") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.showNotification("保存失败：\(error.localizedDescription)")
                }
                print("Save error: \(error)")
            }
        }
    }
    
    private func showNotification(_ message: String) {
        let notification = NSUserNotification()
        notification.title = "MacScreenCapture"
        notification.informativeText = message
        notification.soundName = NSUserNotificationDefaultSoundName
        
        NSUserNotificationCenter.default.deliver(notification)
        
        showInWindowNotification(message)
    }
    
    private func showInWindowNotification(_ message: String) {
        guard let contentView = window?.contentView else { return }
        
        let notificationView = NSView()
        notificationView.wantsLayer = true
        notificationView.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        notificationView.layer?.cornerRadius = 8
        
        let label = NSTextField(labelWithString: message)
        label.textColor = .white
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.alignment = .center
        
        notificationView.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: notificationView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: notificationView.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: notificationView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: notificationView.trailingAnchor, constant: -16)
        ])
        
        contentView.addSubview(notificationView)
        notificationView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            notificationView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            notificationView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            notificationView.heightAnchor.constraint(equalToConstant: 40),
            notificationView.widthAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
        
        notificationView.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            notificationView.animator().alphaValue = 1.0
        } completionHandler: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    notificationView.animator().alphaValue = 0
                } completionHandler: {
                    notificationView.removeFromSuperview()
                }
            }
        }
    }
}

// MARK: - Window Delegate
extension EditingWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onWindowClose?(self)
    }
    
    func windowDidResize(_ notification: Notification) {
        if let window = window {
            UserDefaults.standard.set(NSStringFromSize(window.frame.size), forKey: "lastEditingWindowSize")
        }
    }
    
    func windowDidMove(_ notification: Notification) {
        if let window = window {
            UserDefaults.standard.set(NSStringFromPoint(window.frame.origin), forKey: "lastEditingWindowPosition")
        }
    }
}