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
    case numbered = "numbered"
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
        case .numbered: return "1.circle"
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
        case .numbered: return "序号"
        case .mosaic: return "马赛克"
        case .crop: return "裁剪"
        }
    }
}

// MARK: - Editing Operation
struct EditingOperation: Identifiable, Codable {
    let id: UUID
    let type: EditingTool
    let points: [CGPoint]
    let color: CodableColor
    let lineWidth: CGFloat
    let text: String?
    let rect: CGRect?
    let fontSize: CGFloat?
    let textOutlined: Bool
    let timestamp: Date

    init(
        id: UUID = UUID(),
        type: EditingTool,
        points: [CGPoint] = [],
        color: NSColor = .red,
        lineWidth: CGFloat = 2.0,
        text: String? = nil,
        rect: CGRect? = nil,
        fontSize: CGFloat? = nil,
        textOutlined: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.points = points
        self.color = CodableColor(color: color)
        self.lineWidth = lineWidth
        self.text = text
        self.rect = rect
        self.fontSize = fontSize
        self.textOutlined = textOutlined
        self.timestamp = timestamp
    }

    var resolvedAnnotationFontSize: CGFloat {
        fontSize.map { min(max($0, 10), 72) } ?? max(14, lineWidth * 8)
    }

    var resolvedNumberedMarkerDiameter: CGFloat {
        max(24, resolvedAnnotationFontSize / 0.52)
    }

    func moved(by offset: CGSize) -> EditingOperation {
        EditingOperation(
            id: id,
            type: type,
            points: points.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) },
            color: color.nsColor,
            lineWidth: lineWidth,
            text: text,
            rect: rect?.offsetBy(dx: offset.width, dy: offset.height),
            fontSize: fontSize,
            textOutlined: textOutlined,
            timestamp: timestamp
        )
    }

    func replacingText(with newText: String) -> EditingOperation {
        EditingOperation(
            id: id,
            type: type,
            points: points,
            color: color.nsColor,
            lineWidth: lineWidth,
            text: newText,
            rect: rect,
            fontSize: fontSize,
            textOutlined: textOutlined,
            timestamp: timestamp
        )
    }

    func replacingFontSize(with newFontSize: CGFloat) -> EditingOperation {
        EditingOperation(
            id: id,
            type: type,
            points: points,
            color: color.nsColor,
            lineWidth: lineWidth,
            text: text,
            rect: rect,
            fontSize: newFontSize,
            textOutlined: textOutlined,
            timestamp: timestamp
        )
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
    @Published var resetRevision = 0

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

    func updateOperation(_ operation: EditingOperation) {
        guard let index = operations.firstIndex(where: { $0.id == operation.id }) else { return }
        operations[index] = operation
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
        resetRevision += 1
    }

    private func updateCurrentImage() {
        currentImage = renderImageWithOperations(originalImage, operations: operations)
    }

    private func renderImageWithOperations(_ baseImage: NSImage, operations: [EditingOperation]) -> NSImage {
        var renderedImage = baseImage

        for operation in operations {
            if operation.type == .crop {
                renderedImage = cropImage(renderedImage, to: operation.rect) ?? renderedImage
            } else {
                renderedImage = renderImage(renderedImage, applying: operation)
            }
        }

        return renderedImage
    }

    private func renderImage(_ baseImage: NSImage, applying operation: EditingOperation) -> NSImage {
        let size = baseImage.size
        let image = NSImage(size: size)

        image.lockFocus()

        baseImage.draw(in: NSRect(origin: .zero, size: size))
        applyOperation(operation, in: NSRect(origin: .zero, size: size))

        image.unlockFocus()

        return image
    }

    private func cropImage(_ image: NSImage, to rect: CGRect?) -> NSImage? {
        guard let rect else { return nil }

        let imageBounds = CGRect(origin: .zero, size: image.size)
        let cropRect = rect.intersection(imageBounds).integral
        guard cropRect.width >= 2, cropRect.height >= 2 else { return nil }

        let croppedImage = NSImage(size: cropRect.size)
        croppedImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: cropRect.size),
            from: cropRect,
            operation: .copy,
            fraction: 1.0
        )
        croppedImage.unlockFocus()

        return croppedImage
    }

    private func applyOperation(_ operation: EditingOperation, in rect: NSRect) {
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
        case .numbered:
            drawNumberedMarker(operation, in: rect)
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

        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: operation.resolvedAnnotationFontSize),
            .foregroundColor: operation.color.nsColor
        ]
        if operation.textOutlined {
            attributes[.strokeColor] = NSColor.white
            attributes[.strokeWidth] = -3.0
        }

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        attributedString.draw(in: drawRect)
    }

    private func drawNumberedMarker(_ operation: EditingOperation, in rect: NSRect) {
        guard let text = operation.text else { return }
        let center: CGPoint
        if let point = operation.points.first {
            center = point
        } else if let rect = operation.rect {
            center = CGPoint(x: rect.midX, y: rect.midY)
        } else {
            center = .zero
        }
        let diameter = operation.resolvedNumberedMarkerDiameter
        let markerRect = NSRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )

        let path = NSBezierPath(ovalIn: markerRect)
        operation.color.nsColor.setFill()
        path.fill()

        NSColor.white.setStroke()
        path.lineWidth = max(1.5, operation.lineWidth / 2)
        path.stroke()

        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: operation.resolvedAnnotationFontSize, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                return style
            }()
        ]
        if operation.textOutlined {
            attributes[.strokeColor] = NSColor.black
            attributes[.strokeWidth] = -4.0
        }

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textRect = markerRect.insetBy(dx: 2, dy: (diameter - attributedString.size().height) / 2)
        attributedString.draw(in: textRect)
    }

    private func applyMosaicEffect(_ operation: EditingOperation, in rect: NSRect) {
        // 简化的马赛克效果实现
        guard let drawRect = operation.rect else { return }

        let mosaicSize: CGFloat = 10

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
    var onWindowClose: ((FloatingWindowController) -> Void)?

    init(screenshot: NSImage) {
        self.screenshot = screenshot
        self.editingSession = ImageEditingSession(originalImage: screenshot)

        let windowSize = FloatingWindowConfiguration.preferredWindowSize(for: screenshot.size)

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
        let configuration = FloatingWindowConfiguration.fromDefaults()

        // 窗口属性设置
        window.title = "截图预览"
        window.level = configuration.windowLevel
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)

        // 设置窗口样式为更现代的浮窗样式
        window.hasShadow = configuration.showShadow
        window.isOpaque = false
        window.backgroundColor = NSColor.clear

        // 居中显示
        window.center()

        // 设置最小尺寸
        window.minSize = NSSize(width: 400, height: 300)

        // 窗口动画
        window.animationBehavior = .documentWindow

        // 窗口关闭时的处理
        window.delegate = self

        // 确保窗口始终置顶
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // 添加窗口出现动画
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = configuration.opacity
        }
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
        // 在后台线程处理图片数据，避免阻塞UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                // 获取图片的 TIFF 数据
                guard let tiffData = image.tiffRepresentation else {
                    DispatchQueue.main.async {
                        self.showNotification("保存失败：无法获取图片数据")
                    }
                    return
                }

                // 创建位图表示
                guard let bitmapRep = NSBitmapImageRep(data: tiffData) else {
                    DispatchQueue.main.async {
                        self.showNotification("保存失败：无法处理图片格式")
                    }
                    return
                }

                // 根据文件扩展名确定保存格式
                let fileType: NSBitmapImageRep.FileType
                let properties: [NSBitmapImageRep.PropertyKey: Any]

                switch url.pathExtension.lowercased() {
                case "jpg", "jpeg":
                    fileType = .jpeg
                    properties = [.compressionFactor: 0.9] // JPEG 质量
                case "tiff", "tif":
                    fileType = .tiff
                    properties = [:]
                default:
                    fileType = .png
                    properties = [:]
                }

                // 生成文件数据
                guard let data = bitmapRep.representation(using: fileType, properties: properties) else {
                    DispatchQueue.main.async {
                        self.showNotification("保存失败：无法生成文件数据")
                    }
                    return
                }

                // 确保目录存在
                let directory = url.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
                }

                // 写入文件
                try data.write(to: url)

                // 回到主线程更新UI
                DispatchQueue.main.async {
                    CaptureManager.shared.markScreenshotSaved(image, at: url)
                    self.showNotification("保存成功：\(url.lastPathComponent)")
                    if FloatingWindowConfiguration.fromDefaults().closeAfterSave {
                        self.close()
                    }

                    // 可选：在 Finder 中显示保存的文件
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

        // 创建临时提示视图
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

        // 动画显示和隐藏
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
extension FloatingWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // 窗口关闭时的清理工作
        onWindowClose?(self)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // 窗口获得焦点时确保置顶
        let configuration = FloatingWindowConfiguration.fromDefaults()
        if configuration.alwaysOnTop {
            window?.level = configuration.windowLevel
        }
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        // 当窗口被遮挡状态改变时，确保置顶设置
        let configuration = FloatingWindowConfiguration.fromDefaults()
        if configuration.alwaysOnTop {
            window?.level = configuration.windowLevel
        }
    }

    func windowDidResize(_ notification: Notification) {
        // 窗口大小改变时保存用户偏好
        if let window = window {
            UserDefaults.standard.set(NSStringFromSize(window.frame.size), forKey: "lastFloatingWindowSize")
        }
    }

    func windowDidMove(_ notification: Notification) {
        // 窗口位置改变时保存用户偏好
        if let window = window {
            UserDefaults.standard.set(NSStringFromPoint(window.frame.origin), forKey: "lastFloatingWindowPosition")
        }
    }
}
