import SwiftUI
import Cocoa

struct EditingWindowContentView: View {
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
            // 编辑工具栏
            if isToolbarVisible {
                editingToolbar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(Color(NSColor.separatorColor)),
                        alignment: .bottom
                    )
            }
            
            // 主画布区域 - 只负责编辑，不处理窗口拖拽
            canvasArea
            
            // 底部操作栏
            if isActionBarVisible {
                actionBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(Color(NSColor.separatorColor)),
                        alignment: .top
                    )
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Editing Toolbar
    private var editingToolbar: some View {
        HStack(spacing: 16) {
            // 工具选择
            HStack(spacing: 8) {
                ForEach(EditingTool.allCases, id: \.self) { tool in
                    Button(action: {
                        selectedTool = tool
                        isEditing = tool != .none
                    }) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 16))
                            .foregroundColor(selectedTool == tool ? .white : .primary)
                            .frame(width: 36, height: 36)
                            .background(
                                selectedTool == tool ? Color.accentColor : Color.clear
                            )
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .help(tool.name)
                }
            }
            
            Divider()
                .frame(height: 28)
            
            // 颜色选择
            Button(action: { showingColorPicker.toggle() }) {
                Circle()
                    .fill(selectedColor)
                    .frame(width: 28, height: 28)
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
                .frame(height: 28)
            
            // 线宽调整
            HStack(spacing: 8) {
                Text("粗细")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Slider(value: $lineWidth, in: 1...10, step: 1)
                    .frame(width: 100)
                
                Text("\(Int(lineWidth))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 20)
            }
            
            Spacer()
            
            // 撤销重做
            HStack(spacing: 8) {
                Button(action: {
                    editingSession.undo()
                }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .disabled(!editingSession.canUndo)
                .help("撤销")
                
                Button(action: {
                    editingSession.redo()
                }) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .disabled(!editingSession.canRedo)
                .help("重做")
            }
            
            // 工具栏切换按钮
            Button(action: toggleToolbars) {
                Image(systemName: isToolbarVisible ? "chevron.up" : "chevron.down")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("显示/隐藏工具栏")
        }
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
                
                // 编辑画布 - 专注于编辑功能，不处理窗口拖拽
                EditingCanvas(
                    editingSession: editingSession,
                    selectedTool: selectedTool,
                    selectedColor: selectedColor,
                    lineWidth: lineWidth
                )
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(Color(NSColor.textBackgroundColor))
        .clipped()
    }
    
    // MARK: - Action Bar
    private var actionBar: some View {
        HStack(spacing: 16) {
            Button("保存", action: { onSave(generateFinalImage()) })
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
            
            Button("复制", action: { onCopy(generateFinalImage()) })
                .buttonStyle(.bordered)
                .keyboardShortcut("c", modifiers: .command)
            
            Button("分享", action: { onShare(generateFinalImage()) })
                .buttonStyle(.bordered)
            
            Button("清除所有", action: {
                editingSession.clear()
            })
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            
            Spacer()
            
            Button("关闭", action: onClose)
                .buttonStyle(.bordered)
                .keyboardShortcut("w", modifiers: .command)
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
        
        if operation.points.count > 1 {
            context.beginPath()
            context.move(to: operation.points[0])
            
            for point in operation.points.dropFirst() {
                context.addLine(to: point)
            }
            
            context.strokePath()
        } else if operation.points.count == 1 {
            let point = operation.points[0]
            context.fillEllipse(in: CGRect(
                x: point.x - operation.lineWidth/2,
                y: point.y - operation.lineWidth/2,
                width: operation.lineWidth,
                height: operation.lineWidth
            ))
        }
    }
}

// MARK: - Editing Canvas (专注于编辑功能)
struct EditingCanvas: NSViewRepresentable {
    @ObservedObject var editingSession: ImageEditingSession
    let selectedTool: EditingTool
    let selectedColor: Color
    let lineWidth: CGFloat
    
    func makeNSView(context: Context) -> EditingCanvasView {
        let canvasView = EditingCanvasView()
        canvasView.editingSession = editingSession
        canvasView.delegate = context.coordinator
        return canvasView
    }
    
    func updateNSView(_ nsView: EditingCanvasView, context: Context) {
        nsView.selectedTool = selectedTool
        nsView.selectedColor = NSColor(selectedColor)
        nsView.lineWidth = lineWidth
        nsView.needsDisplay = true
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, EditingCanvasDelegate {
        let parent: EditingCanvas
        
        init(_ parent: EditingCanvas) {
            self.parent = parent
        }
        
        func canvasDidAddOperation(_ operation: EditingOperation) {
            parent.editingSession.addOperation(operation)
        }
    }
}

// MARK: - Editing Canvas View (只处理编辑，不处理窗口拖拽)
protocol EditingCanvasDelegate: AnyObject {
    func canvasDidAddOperation(_ operation: EditingOperation)
}

class EditingCanvasView: NSView {
    weak var delegate: EditingCanvasDelegate?
    var editingSession: ImageEditingSession?
    var selectedTool: EditingTool = .none
    var selectedColor: NSColor = .red
    var lineWidth: CGFloat = 2.0
    
    private var currentPoints: [CGPoint] = []
    private var isDrawing = false
    
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
        // 确保画布始终接受鼠标事件
        acceptsTouchEvents = true
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
        
        let path = NSBezierPath()
        
        if currentPoints.count == 1 {
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
        guard selectedTool != .none, isDrawing else { return }
        
        let location = convert(event.locationInWindow, from: nil)
        currentPoints.append(location)
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard selectedTool != .none, isDrawing, !currentPoints.isEmpty else {
            isDrawing = false
            return
        }
        
        let operation = EditingOperation(
            type: selectedTool,
            points: currentPoints,
            color: selectedColor,
            lineWidth: lineWidth
        )
        
        delegate?.canvasDidAddOperation(operation)
        
        currentPoints.removeAll()
        isDrawing = false
        needsDisplay = true
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    // 确保画布始终接受鼠标事件，不传递给父视图
    override func hitTest(_ point: NSPoint) -> NSView? {
        if bounds.contains(point) {
            return self
        }
        return super.hitTest(point)
    }
}

#Preview {
    let previewImage = NSImage(systemSymbolName: "photo", accessibilityDescription: nil) ?? NSImage()
    return EditingWindowContentView(
        screenshot: previewImage,
        editingSession: ImageEditingSession(originalImage: previewImage),
        onSave: { _ in },
        onCopy: { _ in },
        onShare: { _ in },
        onClose: { }
    )
    .frame(width: 700, height: 600)
}