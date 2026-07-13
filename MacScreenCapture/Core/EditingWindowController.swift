import Foundation
import SwiftUI
import Cocoa
import Carbon

// MARK: - Editing Window Controller
class EditingWindowController: NSWindowController {
    private var screenshot: NSImage
    private var editingSession: ImageEditingSession
    var onWindowClose: ((EditingWindowController) -> Void)?
    
    init(screenshot: NSImage) {
        self.screenshot = screenshot
        self.editingSession = ImageEditingSession(originalImage: screenshot)

        let window = EditingWindow(
            contentRect: Self.fullScreenEditingFrame(),
            styleMask: [.borderless],
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
        
        // 截图后编辑器使用无标题栏全屏遮罩，避免表现成普通 panel/window。
        window.level = .floating
        window.backgroundColor = NSColor.black.withAlphaComponent(0.36)
        window.hasShadow = false
        window.isOpaque = true
        window.isMovableByWindowBackground = false
        window.animationBehavior = .none

        // 窗口关闭时的处理
        window.delegate = self

        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ScreenshotGeometryDiagnostics.logEditorWindowOpened(
            imageSize: screenshot.size,
            windowFrame: window.frame
        )

        // 添加窗口出现动画
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }
    }

    private static func fullScreenEditingFrame() -> NSRect {
        let combinedFrame = NSScreen.screens
            .map(\.frame)
            .reduce(CGRect.null) { partial, screenFrame in
                partial.isNull ? screenFrame : partial.union(screenFrame)
            }

        guard !combinedFrame.isNull, !combinedFrame.isEmpty else {
            return NSRect(x: 0, y: 0, width: 900, height: 700)
        }

        return combinedFrame.integral
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
            onClear: { [weak self] in
                self?.clearEditing()
            },
            onClose: { [weak self] in
                self?.closeEditingWindow()
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

    private func clearEditing() {
        DispatchQueue.main.async { [weak self] in
            self?.editingSession.clear()
        }
    }

    private func closeEditingWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if let window = self.window {
                window.close()
            } else {
                self.close()
            }
        }
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
                    CaptureManager.shared.markScreenshotSaved(image, at: url)
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
        SystemNotificationPresenter.deliverLegacy(message: message)
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

final class EditingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            close()
            return
        }

        super.keyDown(with: event)
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
