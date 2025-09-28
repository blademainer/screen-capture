import Foundation
import SwiftUI
import Cocoa
import Combine

// MARK: - Editing Tools
enum EditingTool: String, CaseIterable, Codable {
    case none = "none"
    case pen = "pen"
    case highlighter = "highlighter"
    case rectangle = "rectangle"
    case circle = "circle"
    case arrow = "arrow"
    case text = "text"
    case mosaic = "mosaic"
    case crop = "crop"
    
    var icon: String {
        switch self {
        case .none: return "hand.point.up.left"
        case .pen: return "pencil"
        case .highlighter: return "highlighter"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        case .mosaic: return "mosaic"
        case .crop: return "crop"
        }
    }
    
    var name: String {
        switch self {
        case .none: return "选择"
        case .pen: return "画笔"
        case .highlighter: return "荧光笔"
        case .rectangle: return "矩形"
        case .circle: return "圆形"
        case .arrow: return "箭头"
        case .text: return "文字"
        case .mosaic: return "马赛克"
        case .crop: return "裁剪"
        }
    }
}

// MARK: - Editing Operation
struct EditingOperation: Identifiable, Codable {
    let id = UUID()
    let type: EditingTool
    let points: [CGPoint]
    let color: CodableColor
    let lineWidth: CGFloat
    let text: String?
    let rect: CGRect?
    let timestamp: Date
    
    init(type: EditingTool, points: [CGPoint] = [], color: NSColor = .red, lineWidth: CGFloat = 2.0, text: String? = nil, rect: CGRect? = nil) {
        self.type = type
        self.points = points
        self.color = CodableColor(color: color)
        self.lineWidth = lineWidth
        self.text = text
        self.rect = rect
        self.timestamp = Date()
    }
}

// MARK: - Codable Color
struct CodableColor: Codable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat
    
    init(color: NSColor) {
        let rgbColor = color.usingColorSpace(.sRGB) ?? color
        self.red = rgbColor.redComponent
        self.green = rgbColor.greenComponent
        self.blue = rgbColor.blueComponent
        self.alpha = rgbColor.alphaComponent
    }
    
    var nsColor: NSColor {
        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    
    var color: Color {
        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

// MARK: - Image Editing Session
class ImageEditingSession: ObservableObject {
    @Published var operations: [EditingOperation] = []
    @Published var currentImage: NSImage
    
    private let originalImage: NSImage
    private var undoStack: [EditingOperation] = []
    private var redoStack: [EditingOperation] = []
    
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    
    init(originalImage: NSImage) {
        self.originalImage = originalImage
        self.currentImage = originalImage
    }
    
    func addOperation(_ operation: EditingOperation) {
        operations.append(operation)
        undoStack.append(operation)
        redoStack.removeAll()
        
        updateCurrentImage()
    }
    
    func undo() {
        guard let lastOperation = undoStack.popLast() else { return }
        
        redoStack.append(lastOperation)
        if let index = operations.firstIndex(where: { $0.id == lastOperation.id }) {
            operations.remove(at: index)
        }
        
        updateCurrentImage()
    }
    
    func redo() {
        guard let operation = redoStack.popLast() else { return }
        
        operations.append(operation)
        undoStack.append(operation)
        
        updateCurrentImage()
    }
    
    func clear() {
        operations.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        currentImage = originalImage
    }
    
    private func updateCurrentImage() {
        currentImage = renderImageWithOperations(originalImage, operations: operations)
    }
    
    private func renderImageWithOperations(_ baseImage: NSImage, operations: [EditingOperation]) -> NSImage {
        let size = baseImage.size
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        // 绘制原始图片
        baseImage.draw(in: NSRect(origin: .zero, size: size))
        
        // 应用所有编辑操作
        for operation in operations {
            applyOperation(operation, in: NSRect(origin: .zero, size: size))
        }
        
        image.unlockFocus()
        
        return image
    }
    
    private func applyOperation(_ operation: EditingOperation, in rect: NSRect) {
        let context = NSGraphicsContext.current?.cgContext
        
        switch operation.type {
        case .pen, .highlighter:
            drawStroke(operation, in: rect)
        case .rectangle:
            drawRectangle(operation, in: rect)
        case .circle:
            drawCircle(operation, in: rect)
        case .arrow:
            drawArrow(operation, in: rect)
        case .text:
            drawText(operation, in: rect)
        case .mosaic:
            applyMosaicEffect(operation, in: rect)
        default:
            break
        }
    }
    
    private func drawStroke(_ operation: EditingOperation, in rect: NSRect) {
        guard operation.points.count > 1 else { return }
        
        let path = NSBezierPath()
        path.move(to: operation.points[0])
        
        for point in operation.points.dropFirst() {
            path.line(to: point)
        }
        
        path.lineWidth = operation.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        
        if operation.type == .highlighter {
            operation.color.nsColor.withAlphaComponent(0.5).setStroke()
        } else {
            operation.color.nsColor.setStroke()
        }
        
        path.stroke()
    }
    
    private func drawRectangle(_ operation: EditingOperation, in rect: NSRect) {
        guard let drawRect = operation.rect else { return }
        
        let path = NSBezierPath(rect: drawRect)
        path.lineWidth = operation.lineWidth
        
        operation.color.nsColor.setStroke()
        path.stroke()
    }
    
    private func drawCircle(_ operation: EditingOperation, in rect: NSRect) {
        guard let drawRect = operation.rect else { return }
        
        let path = NSBezierPath(ovalIn: drawRect)
        path.lineWidth = operation.lineWidth
        
        operation.color.nsColor.setStroke()
        path.stroke()
    }
    
    private func drawArrow(_ operation: EditingOperation, in rect: NSRect) {
        guard operation.points.count >= 2 else { return }
        
        let start = operation.points[0]
        let end = operation.points[1]
        
        // 绘制箭头线
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = operation.lineWidth
        
        operation.color.nsColor.setStroke()
        path.stroke()
        
        // 绘制箭头头部
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 15
        let arrowAngle: CGFloat = .pi / 6
        
        let arrowPath = NSBezierPath()
        arrowPath.move(to: end)
        arrowPath.line(to: CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        ))
        arrowPath.move(to: end)
        arrowPath.line(to: CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        ))
        
        arrowPath.lineWidth = operation.lineWidth
        arrowPath.stroke()
    }
    
    private func drawText(_ operation: EditingOperation, in rect: NSRect) {
        guard let text = operation.text, let drawRect = operation.rect else { return }
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: operation.color.nsColor
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        attributedString.draw(in: drawRect)
    }
    
    private func applyMosaicEffect(_ operation: EditingOperation, in rect: NSRect) {
        // 简化的马赛克效果实现
        guard let drawRect = operation.rect else { return }
        
        let mosaicSize: CGFloat = 10
        let context = NSGraphicsContext.current?.cgContext
        
        for x in stride(from: drawRect.minX, to: drawRect.maxX, by: mosaicSize) {
            for y in stride(from: drawRect.minY, to: drawRect.maxY, by: mosaicSize) {
                let blockRect = CGRect(x: x, y: y, width: mosaicSize, height: mosaicSize)
                
                // 用随机颜色填充块（简化实现）
                let grayValue = CGFloat.random(in: 0.3...0.7)
                NSColor(white: grayValue, alpha: 1.0).setFill()
                blockRect.fill()
            }
        }
    }
}

// MARK: - Floating Window Controller
class FloatingWindowController: NSWindowController {
    private var screenshot: NSImage
    private var editingSession: ImageEditingSession
    
    init(screenshot: NSImage) {
        self.screenshot = screenshot
        self.editingSession = ImageEditingSession(originalImage: screenshot)
        
        // 计算窗口尺寸
        let imageSize = screenshot.size
        let maxSize = CGSize(width: 800, height: 600)
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
        windowSize.height += 120
        
        // 创建浮窗
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
        
        // 窗口属性设置
        window.title = "截图预览"
        window.level = .floating  // 置顶显示
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        
        // 居中显示
        window.center()
        
        // 设置最小尺寸
        window.minSize = NSSize(width: 400, height: 300)
        
        // 窗口动画
        window.animationBehavior = .documentWindow
        
        // 窗口关闭时的处理
        window.delegate = self
    }
    
    private func setupContent() {
        let contentView = FloatingWindowContentView(
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
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg, .tiff]
        savePanel.nameFieldStringValue = "Screenshot_\(Date().timeIntervalSince1970).png"
        
        savePanel.begin { [weak self] result in
            if result == .OK, let url = savePanel.url {
                self?.writeImage(image, to: url)
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
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            showNotification("保存失败：无法处理图片")
            return
        }
        
        let fileType: NSBitmapImageRep.FileType
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            fileType = .jpeg
        case "tiff", "tif":
            fileType = .tiff
        default:
            fileType = .png
        }
        
        guard let data = bitmapRep.representation(using: fileType, properties: [:]) else {
            showNotification("保存失败：无法生成文件数据")
            return
        }
        
        do {
            try data.write(to: url)
            showNotification("保存成功")
        } catch {
            showNotification("保存失败：\(error.localizedDescription)")
        }
    }
    
    private func showNotification(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
}

// MARK: - Window Delegate
extension FloatingWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // 窗口关闭时的清理工作
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        // 窗口获得焦点时确保置顶
        window?.level = .floating
    }
}