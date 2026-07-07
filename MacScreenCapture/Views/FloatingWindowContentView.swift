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
    @State private var isEditing = false
    @State private var showingColorPicker = false
    @State private var isToolbarVisible = true
    @State private var isActionBarVisible = true

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
                Image(nsImage: screenshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 编辑画布 - 使用基于现有ImageEditingSession的传统画布
                TraditionalEditingCanvas(
                    editingSession: editingSession,
                    selectedTool: selectedTool,
                    selectedColor: selectedColor,
                    lineWidth: lineWidth
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
        // 合成最终图片（原图 + 编辑内容）
        let finalSize = screenshot.size
        let finalImage = NSImage(size: finalSize)

        finalImage.lockFocus()

        // 绘制原始截图
        screenshot.draw(in: NSRect(origin: .zero, size: finalSize))

        // 绘制编辑内容
        for operation in editingSession.operations {
            drawOperation(operation, in: NSRect(origin: .zero, size: finalSize))
        }

        finalImage.unlockFocus()

        return finalImage
    }

    private func drawOperation(_ operation: EditingOperation, in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.setStrokeColor(operation.color.nsColor.cgColor)
        context.setLineWidth(operation.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch operation.type {
        case .pen, .highlighter:
            guard operation.points.count > 1 else { return }
            context.beginPath()
            context.move(to: operation.points[0])

            for point in operation.points.dropFirst() {
                context.addLine(to: point)
            }

            if operation.type == .highlighter {
                context.setStrokeColor(operation.color.nsColor.withAlphaComponent(0.5).cgColor)
            }
            context.strokePath()
        case .rectangle:
            guard let drawRect = operation.rect else { return }
            context.stroke(drawRect)
        case .circle:
            guard let drawRect = operation.rect else { return }
            context.strokeEllipse(in: drawRect)
        case .arrow:
            drawArrow(operation)
        case .text:
            drawText(operation)
        case .numbered:
            drawNumberedMarker(operation)
        case .mosaic:
            drawMosaic(operation)
        case .none, .crop:
            break
        }
    }

    private func drawArrow(_ operation: EditingOperation) {
        guard operation.points.count >= 2 else { return }
        let start = operation.points[0]
        let end = operation.points[1]
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = operation.lineWidth
        operation.color.nsColor.setStroke()
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

    private func drawText(_ operation: EditingOperation) {
        guard let text = operation.text, let drawRect = operation.rect else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(14, operation.lineWidth * 8)),
            .foregroundColor: operation.color.nsColor
        ]
        NSAttributedString(string: text, attributes: attributes).draw(in: drawRect)
    }

    private func drawNumberedMarker(_ operation: EditingOperation) {
        guard let text = operation.text else { return }
        let center = operation.points.first ?? CGPoint(x: operation.rect?.midX ?? 0, y: operation.rect?.midY ?? 0)
        let diameter = max(24, operation.lineWidth * 9)
        let markerRect = NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        let path = NSBezierPath(ovalIn: markerRect)
        operation.color.nsColor.setFill()
        path.fill()
        NSColor.white.setStroke()
        path.lineWidth = max(1.5, operation.lineWidth / 2)
        path.stroke()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: diameter * 0.52, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textRect = markerRect.insetBy(dx: 2, dy: (diameter - attributedString.size().height) / 2)
        attributedString.draw(in: textRect)
    }

    private func drawMosaic(_ operation: EditingOperation) {
        guard let drawRect = operation.rect else { return }
        let mosaicSize: CGFloat = 10
        for x in stride(from: drawRect.minX, to: drawRect.maxX, by: mosaicSize) {
            for y in stride(from: drawRect.minY, to: drawRect.maxY, by: mosaicSize) {
                NSColor(white: CGFloat.random(in: 0.3...0.7), alpha: 1.0).setFill()
                NSRect(x: x, y: y, width: mosaicSize, height: mosaicSize).fill()
            }
        }
    }
}

// MARK: - Traditional Editing Canvas (基于现有ImageEditingSession方案)
struct TraditionalEditingCanvas: NSViewRepresentable {
    @ObservedObject var editingSession: ImageEditingSession
    let selectedTool: EditingTool
    let selectedColor: Color
    let lineWidth: CGFloat

    func makeNSView(context: Context) -> FloatingEditingCanvasView {
        let canvasView = FloatingEditingCanvasView()
        canvasView.editingSession = editingSession
        canvasView.delegate = context.coordinator
        return canvasView
    }

    func updateNSView(_ nsView: FloatingEditingCanvasView, context: Context) {
        nsView.selectedTool = selectedTool
        nsView.selectedColor = NSColor(selectedColor)
        nsView.lineWidth = lineWidth
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

    private var currentPoints: [CGPoint] = []
    private var isDrawing = false
    private var nextNumber = 1

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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 绘制当前正在绘制的内容
        if !currentPoints.isEmpty && isDrawing {
            drawCurrentStroke()
        }
    }

    private func drawCurrentStroke() {
        guard !currentPoints.isEmpty else { return }
        guard let firstPoint = currentPoints.first, let lastPoint = currentPoints.last else { return }

        if [.rectangle, .circle, .mosaic].contains(selectedTool), currentPoints.count >= 2 {
            let rect = normalizedRect(from: firstPoint, to: lastPoint)
            let path = selectedTool == .circle ? NSBezierPath(ovalIn: rect) : NSBezierPath(rect: rect)
            path.lineWidth = lineWidth
            selectedColor.setStroke()
            path.stroke()
            return
        }

        if selectedTool == .arrow, currentPoints.count >= 2 {
            let operation = EditingOperation(type: .arrow, points: [firstPoint, lastPoint], color: selectedColor, lineWidth: lineWidth)
            drawPreviewArrow(operation)
            return
        }

        let path = NSBezierPath()

        if currentPoints.count == 1 {
            // 单点绘制
            let point = currentPoints[0]
            let rect = CGRect(
                x: point.x - lineWidth/2,
                y: point.y - lineWidth/2,
                width: lineWidth,
                height: lineWidth
            )
            path.appendOval(in: rect)
            selectedColor.setFill()
            path.fill()
        } else {
            // 多点连线
            path.move(to: currentPoints[0])
            for point in currentPoints.dropFirst() {
                path.line(to: point)
            }

            path.lineWidth = lineWidth
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
        guard selectedTool != .none else { return }

        let location = convert(event.locationInWindow, from: nil)
        currentPoints = [location]
        isDrawing = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard selectedTool != .none, selectedTool != .numbered, selectedTool != .text, isDrawing else { return }

        let location = convert(event.locationInWindow, from: nil)
        currentPoints.append(location)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard selectedTool != .none, isDrawing, !currentPoints.isEmpty else {
            isDrawing = false
            return
        }

        let endLocation = convert(event.locationInWindow, from: nil)
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
        case .arrow:
            return EditingOperation(type: selectedTool, points: [firstPoint, lastPoint], color: selectedColor, lineWidth: lineWidth)
        case .text:
            guard let text = requestTextInput(at: firstPoint) else { return nil }
            let textRect = NSRect(x: firstPoint.x, y: firstPoint.y, width: 240, height: max(32, lineWidth * 12))
            return EditingOperation(type: .text, color: selectedColor, lineWidth: lineWidth, text: text, rect: textRect)
        case .numbered:
            let text = "\(nextNumber)"
            nextNumber += 1
            return EditingOperation(type: .numbered, points: [firstPoint], color: selectedColor, lineWidth: lineWidth, text: text, rect: nil)
        case .none, .crop:
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

    private func requestTextInput(at point: CGPoint) -> String? {
        let alert = NSAlert()
        alert.messageText = "添加文字"
        alert.informativeText = "输入要标注的文字"
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
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
}

// MARK: - Editing Toolbar
struct EditingToolbar: View {
    @Binding var selectedTool: EditingTool
    @Binding var selectedColor: Color
    @Binding var lineWidth: CGFloat
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
