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
            // 拖拽图标
            Image(systemName: "move.3d")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("截图编辑")
                .font(.headline)
                .foregroundColor(.primary)
            
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
        .gesture(windowDragGesture)
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
                
                // 编辑画布
                SimpleEditingCanvas(
                    editingSession: editingSession,
                    selectedTool: selectedTool,
                    selectedColor: selectedColor,
                    lineWidth: lineWidth,
                    canvasSize: geometry.size
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
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
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
        
        if operation.points.count > 1 {
            context.beginPath()
            context.move(to: operation.points[0])
            
            for point in operation.points.dropFirst() {
                context.addLine(to: point)
            }
            
            context.strokePath()
        } else if operation.points.count == 1 {
            // 单点绘制
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

// MARK: - Simple Editing Canvas
struct SimpleEditingCanvas: View {
    @ObservedObject var editingSession: ImageEditingSession
    let selectedTool: EditingTool
    let selectedColor: Color
    let lineWidth: CGFloat
    let canvasSize: CGSize
    
    @State private var currentPoints: [CGPoint] = []
    
    var body: some View {
        Canvas { context, size in
            // 绘制所有已完成的操作
            for operation in editingSession.operations {
                drawOperation(context: context, operation: operation)
            }
            
            // 绘制当前正在绘制的内容
            if !currentPoints.isEmpty {
                drawCurrentStroke(context: context)
            }
        }
        .gesture(editingGesture)
        .allowsHitTesting(selectedTool != .none)
    }
    
    private var editingGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard selectedTool != .none else { return }
                currentPoints.append(value.location)
            }
            .onEnded { _ in
                guard selectedTool != .none, !currentPoints.isEmpty else { return }
                
                // 创建新的编辑操作
                let operation = EditingOperation(
                    type: selectedTool,
                    points: currentPoints,
                    color: NSColor(selectedColor),
                    lineWidth: lineWidth
                )
                
                // 保存操作
                editingSession.operations.append(operation)
                currentPoints.removeAll()
            }
    }
    
    private func drawOperation(context: GraphicsContext, operation: EditingOperation) {
        guard !operation.points.isEmpty else { return }
        
        let path = Path { path in
            if operation.points.count == 1 {
                // 单点绘制
                let point = operation.points[0]
                path.addEllipse(in: CGRect(
                    x: point.x - operation.lineWidth/2,
                    y: point.y - operation.lineWidth/2,
                    width: operation.lineWidth,
                    height: operation.lineWidth
                ))
            } else {
                // 多点连线
                path.move(to: operation.points[0])
                for point in operation.points.dropFirst() {
                    path.addLine(to: point)
                }
            }
        }
        
        context.stroke(
            path,
            with: .color(operation.color.color),
            style: StrokeStyle(
                lineWidth: operation.lineWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )
    }
    
    private func drawCurrentStroke(context: GraphicsContext) {
        guard !currentPoints.isEmpty else { return }
        
        let path = Path { path in
            if currentPoints.count == 1 {
                // 单点绘制
                let point = currentPoints[0]
                path.addEllipse(in: CGRect(
                    x: point.x - lineWidth/2,
                    y: point.y - lineWidth/2,
                    width: lineWidth,
                    height: lineWidth
                ))
            } else {
                // 多点连线
                path.move(to: currentPoints[0])
                for point in currentPoints.dropFirst() {
                    path.addLine(to: point)
                }
            }
        }
        
        context.stroke(
            path,
            with: .color(selectedColor),
            style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )
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