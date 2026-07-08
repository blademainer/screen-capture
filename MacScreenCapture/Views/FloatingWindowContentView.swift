import SwiftUI
import Cocoa

struct FloatingWindowContentView: View {
    let screenshot: NSImage
    @ObservedObject var editingSession: ImageEditingSession

    let onSave: (NSImage) -> Void
    let onCopy: (NSImage) -> Void
    let onShare: (NSImage) -> Void
    let onClose: () -> Void

    @State private var selectedTool: EditingTool = .none
    @State private var selectedColor: Color = .red
    @State private var lineWidth: CGFloat = 2.0
    @State private var fontSize: CGFloat = 18.0
    @State private var isEditing = false
    @State private var showingColorPicker = false
    @State private var isToolbarVisible = true
    @State private var isActionBarVisible = true
    @AppStorage("annotationDefaultColorHex") private var annotationDefaultColorHex = AnnotationStylePreset.professional.colorHex
    @AppStorage("annotationDefaultLineWidth") private var annotationDefaultLineWidth = AnnotationStylePreset.professional.lineWidth
    @AppStorage("annotationDefaultFontSize") private var annotationDefaultFontSize = AnnotationStylePreset.professional.fontSize
    @AppStorage("annotationTextOutlined") private var textOutlined = false

    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏（简单拖拽区域）
            titleBar

            // 编辑工具栏
            if isToolbarVisible {
                editingToolbar
            }

            // 主画布区域
            canvasArea

            // 底部操作栏
            if isActionBarVisible {
                actionBar
            }
        }
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            selectedColor = .annotationDefault(hex: annotationDefaultColorHex)
            lineWidth = CGFloat(annotationDefaultLineWidth)
            fontSize = CGFloat(annotationDefaultFontSize)
        }
    }

    // MARK: - Title Bar
    private var titleBar: some View {
        HStack {
            // 拖拽区域 - 只有这个区域可以拖拽窗口
            HStack {
                Image(systemName: "move.3d")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("截图编辑")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: 120)
            .contentShape(Rectangle())
            .gesture(windowDragGesture)

            Spacer()

            // 工具栏切换按钮
            Button(action: toggleToolbars) {
                Image(systemName: isToolbarVisible ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            // 关闭按钮
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            VisualEffectView(material: .titlebar, blendingMode: .behindWindow)
        )
    }

    // MARK: - Editing Toolbar
    private var editingToolbar: some View {
        EditingToolbar(
            selectedTool: $selectedTool,
            selectedColor: $selectedColor,
            lineWidth: $lineWidth,
            fontSize: $fontSize,
            textOutlined: $textOutlined,
            showingColorPicker: $showingColorPicker,
            onToolSelected: { tool in
                selectedTool = tool
                isEditing = tool != .none
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Canvas Area
    private var canvasArea: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景图片
                Image(nsImage: editingSession.currentImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 编辑画布 - 使用基于现有ImageEditingSession的传统画布
                TraditionalEditingCanvas(
                    editingSession: editingSession,
                    selectedTool: selectedTool,
                    selectedColor: selectedColor,
                    lineWidth: lineWidth,
                    fontSize: fontSize,
                    textOutlined: textOutlined
                )
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(Color.black.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal, 16)
    }

    // MARK: - Action Bar
    private var actionBar: some View {
        QuickActionBar(
            onSave: { onSave(generateFinalImage()) },
            onCopy: { onCopy(generateFinalImage()) },
            onShare: { onShare(generateFinalImage()) },
            onClose: onClose
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Window Drag Gesture
    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                // 只有在拖拽距离足够大时才移动窗口，避免意外触发
                guard let window = NSApp.keyWindow else { return }

                let newLocation = CGPoint(
                    x: value.location.x - value.startLocation.x + window.frame.origin.x,
                    y: value.location.y - value.startLocation.y + window.frame.origin.y
                )
                window.setFrameOrigin(newLocation)
            }
    }

    // MARK: - Helper Methods
    private func toggleToolbars() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isToolbarVisible.toggle()
            isActionBarVisible.toggle()
        }
    }

    private func generateFinalImage() -> NSImage {
        editingSession.currentImage
    }
}

// MARK: - Traditional Editing Canvas (基于现有ImageEditingSession方案)
struct TraditionalEditingCanvas: NSViewRepresentable {
    @ObservedObject var editingSession: ImageEditingSession
    let selectedTool: EditingTool
    let selectedColor: Color
    let lineWidth: CGFloat
    let fontSize: CGFloat
    let textOutlined: Bool

    func makeNSView(context: Context) -> FloatingEditingCanvasView {
        let canvasView = FloatingEditingCanvasView()
        canvasView.editingSession = editingSession
        canvasView.delegate = context.coordinator
        return canvasView
    }

    func updateNSView(_ nsView: FloatingEditingCanvasView, context: Context) {
        nsView.imageSize = editingSession.currentImage.size
        nsView.editingSession = editingSession
        nsView.syncResetRevision(editingSession.resetRevision)
        nsView.selectedTool = selectedTool
        nsView.selectedColor = NSColor(selectedColor)
        nsView.lineWidth = lineWidth
        nsView.fontSize = fontSize
        nsView.textOutlined = textOutlined
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, FloatingEditingCanvasDelegate {
        let parent: TraditionalEditingCanvas

        init(_ parent: TraditionalEditingCanvas) {
            self.parent = parent
        }

        func canvasDidAddOperation(_ operation: EditingOperation) {
            parent.editingSession.addOperation(operation)
        }
    }
}

// MARK: - Editing Canvas View
protocol FloatingEditingCanvasDelegate: AnyObject {
    func canvasDidAddOperation(_ operation: EditingOperation)
}

class FloatingEditingCanvasView: NSView {
    weak var delegate: FloatingEditingCanvasDelegate?
    var editingSession: ImageEditingSession?
    var selectedTool: EditingTool = .none
    var selectedColor: NSColor = .red
    var lineWidth: CGFloat = 2.0
    var fontSize: CGFloat = 18.0
    var textOutlined = false
    var imageSize: CGSize = .zero

    private var currentPoints: [CGPoint] = []
    private var isDrawing = false
    private var nextNumber = FloatingEditingCanvasView.defaultNumberStart()
    private var movingOperationID: UUID?
    private var movingStartPoint: CGPoint?
    private var originalMovingOperation: EditingOperation?
    private var observedResetRevision = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    private static func defaultNumberStart() -> Int {
        max(1, UserDefaults.standard.integer(forKey: "numberedAnnotationStart"))
    }

    func syncResetRevision(_ revision: Int) {
        guard revision != observedResetRevision else { return }
        observedResetRevision = revision
        cancelActiveInteraction()
        needsDisplay = true
    }

    private func cancelActiveInteraction() {
        currentPoints.removeAll()
        isDrawing = false
        movingOperationID = nil
        movingStartPoint = nil
        originalMovingOperation = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if !currentPoints.isEmpty && isDrawing {
            drawCurrentStroke()
        }
    }

    private func drawCurrentStroke() {
        guard !currentPoints.isEmpty else { return }
        guard let firstPoint = currentPoints.first, let lastPoint = currentPoints.last else { return }

        if [.rectangle, .circle, .mosaic, .text, .crop].contains(selectedTool), currentPoints.count >= 2 {
            let rect = viewRect(fromImageRect: normalizedRect(from: firstPoint, to: lastPoint))
            let path = selectedTool == .circle ? NSBezierPath(ovalIn: rect) : NSBezierPath(rect: rect)
            path.lineWidth = scaledLineWidth
            selectedColor.setStroke()
            path.stroke()
            return
        }

        if selectedTool == .arrow, currentPoints.count >= 2 {
            let operation = EditingOperation(
                type: .arrow,
                points: [viewPoint(fromImagePoint: firstPoint), viewPoint(fromImagePoint: lastPoint)],
                color: selectedColor,
                lineWidth: scaledLineWidth
            )
            drawPreviewArrow(operation)
            return
        }

        let path = NSBezierPath()
        let viewPoints = currentPoints.map { viewPoint(fromImagePoint: $0) }

        if viewPoints.count == 1 {
            // 单点绘制
            let point = viewPoints[0]
            let rect = CGRect(
                x: point.x - scaledLineWidth / 2,
                y: point.y - scaledLineWidth / 2,
                width: scaledLineWidth,
                height: scaledLineWidth
            )
            path.appendOval(in: rect)
            selectedColor.setFill()
            path.fill()
        } else {
            // 多点连线
            path.move(to: viewPoints[0])
            for point in viewPoints.dropFirst() {
                path.line(to: point)
            }

            path.lineWidth = scaledLineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            if selectedTool == .highlighter {
                selectedColor.withAlphaComponent(0.5).setStroke()
            } else {
                selectedColor.setStroke()
            }

            path.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let location = imagePoint(fromViewPoint: convert(event.locationInWindow, from: nil)) else { return }

        if selectedTool == .none, let operation = hitTestMovableOperation(at: location) {
            if event.clickCount >= 2 {
                editTextOperation(operation)
                return
            }

            movingOperationID = operation.id
            movingStartPoint = location
            originalMovingOperation = operation
            return
        }

        guard selectedTool != .none else { return }

        currentPoints = [location]
        isDrawing = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if let movingOperationID,
           let movingStartPoint,
           let originalMovingOperation,
            originalMovingOperation.id == movingOperationID {
            guard let location = imagePoint(fromViewPoint: convert(event.locationInWindow, from: nil)) else { return }
            let offset = CGSize(
                width: location.x - movingStartPoint.x,
                height: location.y - movingStartPoint.y
            )
            editingSession?.updateOperation(originalMovingOperation.moved(by: offset))
            needsDisplay = true
            return
        }

        guard selectedTool != .none, selectedTool != .numbered, isDrawing else { return }

        guard let location = imagePoint(fromViewPoint: convert(event.locationInWindow, from: nil)) else { return }
        currentPoints.append(location)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if movingOperationID != nil {
            movingOperationID = nil
            movingStartPoint = nil
            originalMovingOperation = nil
            needsDisplay = true
            return
        }

        guard selectedTool != .none, isDrawing, !currentPoints.isEmpty else {
            isDrawing = false
            return
        }

        let endLocation = imagePoint(fromViewPoint: convert(event.locationInWindow, from: nil)) ?? currentPoints.last!
        if currentPoints.last != endLocation {
            currentPoints.append(endLocation)
        }

        guard let operation = makeOperationForCurrentGesture() else {
            currentPoints.removeAll()
            isDrawing = false
            needsDisplay = true
            return
        }

        // 通知代理
        delegate?.canvasDidAddOperation(operation)

        // 重置状态
        currentPoints.removeAll()
        isDrawing = false
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    private func makeOperationForCurrentGesture() -> EditingOperation? {
        guard let firstPoint = currentPoints.first, let lastPoint = currentPoints.last else { return nil }

        switch selectedTool {
        case .pen, .highlighter:
            return EditingOperation(type: selectedTool, points: currentPoints, color: selectedColor, lineWidth: lineWidth)
        case .rectangle, .circle, .mosaic:
            return EditingOperation(type: selectedTool, color: selectedColor, lineWidth: lineWidth, rect: normalizedRect(from: firstPoint, to: lastPoint))
        case .crop:
            let cropRect = normalizedRect(from: firstPoint, to: lastPoint)
            guard cropRect.width >= 8, cropRect.height >= 8 else { return nil }
            return EditingOperation(type: .crop, color: selectedColor, lineWidth: lineWidth, rect: cropRect)
        case .arrow:
            return EditingOperation(type: selectedTool, points: [firstPoint, lastPoint], color: selectedColor, lineWidth: lineWidth)
        case .text:
            guard let text = requestTextInput(title: "添加文字", message: "输入要标注的文字") else { return nil }
            let draggedRect = normalizedRect(from: firstPoint, to: lastPoint)
            let textRect = draggedRect.width >= 24 && draggedRect.height >= 18
                ? draggedRect
                : NSRect(x: firstPoint.x, y: firstPoint.y, width: 240, height: max(32, lineWidth * 12))
            return EditingOperation(type: .text, color: selectedColor, lineWidth: lineWidth, text: text, rect: textRect, fontSize: fontSize, textOutlined: textOutlined)
        case .numbered:
            let text = "\(nextNumber)"
            nextNumber += 1
            return EditingOperation(type: .numbered, points: [firstPoint], color: selectedColor, lineWidth: lineWidth, text: text, rect: nil, fontSize: fontSize, textOutlined: textOutlined)
        case .none:
            return nil
        }
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private var imageDisplayRect: CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }

        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale

        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }

    private var imageScale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return min(bounds.width / imageSize.width, bounds.height / imageSize.height)
    }

    private var scaledLineWidth: CGFloat {
        max(1, lineWidth * imageScale)
    }

    private func imagePoint(fromViewPoint point: CGPoint) -> CGPoint? {
        let rect = imageDisplayRect
        guard rect.contains(point), imageScale > 0 else { return nil }

        return CGPoint(
            x: (point.x - rect.minX) / imageScale,
            y: (point.y - rect.minY) / imageScale
        )
    }

    private func viewPoint(fromImagePoint point: CGPoint) -> CGPoint {
        let rect = imageDisplayRect
        return CGPoint(
            x: rect.minX + point.x * imageScale,
            y: rect.minY + point.y * imageScale
        )
    }

    private func viewRect(fromImageRect rect: CGRect) -> CGRect {
        let origin = viewPoint(fromImagePoint: rect.origin)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: rect.width * imageScale,
            height: rect.height * imageScale
        )
    }

    private func requestTextInput(title: String, message: String, initialValue: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = initialValue
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func editTextOperation(_ operation: EditingOperation) {
        guard operation.type == .text || operation.type == .numbered else { return }

        let title = operation.type == .numbered ? "设置序号" : "编辑文字"
        let message = operation.type == .numbered ? "输入要显示的序号" : "输入要标注的文字"
        guard let newText = requestTextInput(
            title: title,
            message: message,
            initialValue: operation.text ?? ""
        ) else {
            return
        }

        editingSession?.updateOperation(operation.replacingText(with: newText))
        needsDisplay = true
    }

    private func drawPreviewArrow(_ operation: EditingOperation) {
        guard operation.points.count >= 2 else { return }
        let start = operation.points[0]
        let end = operation.points[1]
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = operation.lineWidth
        selectedColor.setStroke()
        path.stroke()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 15
        let arrowAngle: CGFloat = .pi / 6
        let arrowPath = NSBezierPath()
        arrowPath.move(to: end)
        arrowPath.line(to: CGPoint(x: end.x - arrowLength * cos(angle - arrowAngle), y: end.y - arrowLength * sin(angle - arrowAngle)))
        arrowPath.move(to: end)
        arrowPath.line(to: CGPoint(x: end.x - arrowLength * cos(angle + arrowAngle), y: end.y - arrowLength * sin(angle + arrowAngle)))
        arrowPath.lineWidth = operation.lineWidth
        arrowPath.stroke()
    }

    private func hitTestMovableOperation(at point: CGPoint) -> EditingOperation? {
        editingSession?.operations.reversed().first { operation in
            switch operation.type {
            case .text:
                return operation.rect?.insetBy(dx: -6, dy: -6).contains(point) == true
            case .numbered:
                return numberedMarkerRect(for: operation).insetBy(dx: -6, dy: -6).contains(point)
            default:
                return false
            }
        }
    }

    private func drawCommittedOperation(_ operation: EditingOperation) {
        switch operation.type {
        case .pen, .highlighter:
            drawCommittedStroke(operation)
        case .rectangle:
            guard let rect = operation.rect else { return }
            let path = NSBezierPath(rect: rect)
            path.lineWidth = operation.lineWidth
            operation.color.nsColor.setStroke()
            path.stroke()
        case .circle:
            guard let rect = operation.rect else { return }
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = operation.lineWidth
            operation.color.nsColor.setStroke()
            path.stroke()
        case .arrow:
            drawPreviewArrow(operation)
        case .text:
            drawCommittedText(operation)
        case .numbered:
            drawCommittedNumberedMarker(operation)
        case .mosaic:
            guard let rect = operation.rect else { return }
            NSColor.black.withAlphaComponent(0.18).setFill()
            NSBezierPath(rect: rect).fill()
        case .none, .crop:
            break
        }
    }

    private func drawCommittedStroke(_ operation: EditingOperation) {
        guard operation.points.count > 1 else { return }
        let path = NSBezierPath()
        path.move(to: operation.points[0])
        operation.points.dropFirst().forEach { path.line(to: $0) }
        path.lineWidth = operation.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        (operation.type == .highlighter ? operation.color.nsColor.withAlphaComponent(0.5) : operation.color.nsColor).setStroke()
        path.stroke()
    }

    private func drawCommittedText(_ operation: EditingOperation) {
        guard let text = operation.text, let rect = operation.rect else { return }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: operation.resolvedAnnotationFontSize),
            .foregroundColor: operation.color.nsColor
        ]
        if operation.textOutlined {
            attributes[.strokeColor] = NSColor.white
            attributes[.strokeWidth] = -3.0
        }
        NSAttributedString(string: text, attributes: attributes).draw(in: rect)
    }

    private func drawCommittedNumberedMarker(_ operation: EditingOperation) {
        guard let text = operation.text else { return }
        let markerRect = numberedMarkerRect(for: operation)
        let path = NSBezierPath(ovalIn: markerRect)
        operation.color.nsColor.setFill()
        path.fill()
        NSColor.white.setStroke()
        path.lineWidth = max(1.5, operation.lineWidth / 2)
        path.stroke()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: operation.resolvedAnnotationFontSize, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        if operation.textOutlined {
            attributes[.strokeColor] = NSColor.black
            attributes[.strokeWidth] = -4.0
        }

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textRect = markerRect.insetBy(dx: 2, dy: (markerRect.height - attributedString.size().height) / 2)
        attributedString.draw(in: textRect)
    }

    private func numberedMarkerRect(for operation: EditingOperation) -> NSRect {
        let center = operation.points.first ?? CGPoint(x: operation.rect?.midX ?? 0, y: operation.rect?.midY ?? 0)
        let diameter = operation.resolvedNumberedMarkerDiameter
        return NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
    }
}

// MARK: - Editing Toolbar
struct EditingToolbar: View {
    @Binding var selectedTool: EditingTool
    @Binding var selectedColor: Color
    @Binding var lineWidth: CGFloat
    @Binding var fontSize: CGFloat
    @Binding var textOutlined: Bool
    @Binding var showingColorPicker: Bool

    let onToolSelected: (EditingTool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 工具选择
            HStack(spacing: 8) {
                ForEach(EditingTool.allCases, id: \.self) { tool in
                    Button(action: {
                        selectedTool = tool
                        onToolSelected(tool)
                    }) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 16))
                            .foregroundColor(selectedTool == tool ? .white : .primary)
                            .frame(width: 32, height: 32)
                            .background(
                                selectedTool == tool ? Color.accentColor : Color.clear
                            )
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help(tool.name)
                }
            }

            Divider()
                .frame(height: 24)

            // 颜色选择
            Button(action: { showingColorPicker.toggle() }) {
                Circle()
                    .fill(selectedColor)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(Color.primary, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingColorPicker) {
                ColorPicker("选择颜色", selection: $selectedColor)
                    .padding()
            }

            Divider()
                .frame(height: 24)

            // 线宽调整
            HStack {
                Text("粗细")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Slider(value: $lineWidth, in: 1...10, step: 1)
                    .frame(width: 80)

                Text("\(Int(lineWidth))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 20)
            }

            HStack {
                Text("字号")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Slider(value: $fontSize, in: 10...72, step: 1)
                    .frame(width: 88)

                Text("\(Int(fontSize))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 24)
            }
            .disabled(selectedTool != .text && selectedTool != .numbered)

            Toggle("描边", isOn: $textOutlined)
                .toggleStyle(.checkbox)
                .font(.caption)
                .disabled(selectedTool != .text && selectedTool != .numbered)
        }
    }
}

// MARK: - Quick Action Bar
struct QuickActionBar: View {
    let onSave: () -> Void
    let onCopy: () -> Void
    let onShare: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button("保存", action: onSave)
                .buttonStyle(.borderedProminent)

            Button("复制", action: onCopy)
                .buttonStyle(.bordered)

            Button("分享", action: onShare)
                .buttonStyle(.bordered)

            Spacer()

            Button("关闭", action: onClose)
                .buttonStyle(.bordered)
        }
    }
}

// MARK: - Visual Effect View
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#Preview {
    let previewImage = NSImage(systemSymbolName: "photo", accessibilityDescription: nil) ?? NSImage()
    return FloatingWindowContentView(
        screenshot: previewImage,
        editingSession: ImageEditingSession(originalImage: previewImage),
        onSave: { _ in },
        onCopy: { _ in },
        onShare: { _ in },
        onClose: { }
    )
    .frame(width: 600, height: 500)
}
