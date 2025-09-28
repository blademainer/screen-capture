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
        ZStack {
            // 主内容区域
            VStack(spacing: 0) {
                // 顶部工具栏
                if isToolbarVisible {
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
                
                // 图片预览和编辑区域
                GeometryReader { geometry in
                    ImageEditingCanvas(
                        image: screenshot,
                        editingSession: editingSession,
                        selectedTool: selectedTool,
                        selectedColor: selectedColor,
                        lineWidth: lineWidth,
                        canvasSize: geometry.size
                    )
                }
                .background(Color.black.opacity(0.02))
                .onTapGesture(count: 2) {
                    // 双击切换工具栏显示/隐藏
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isToolbarVisible.toggle()
                        isActionBarVisible.toggle()
                    }
                }
                
                // 底部操作栏
                if isActionBarVisible {
                    QuickActionBar(
                        onSave: { onSave(editingSession.currentImage) },
                        onCopy: { onCopy(editingSession.currentImage) },
                        onShare: { onShare(editingSession.currentImage) },
                        onUndo: { editingSession.undo() },
                        onRedo: { editingSession.redo() },
                        onClear: { editingSession.clear() },
                        onClose: onClose,
                        canUndo: editingSession.canUndo,
                        canRedo: editingSession.canRedo,
                        hasOperations: !editingSession.operations.isEmpty
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            
            // 浮动控制按钮（当工具栏隐藏时显示）
            if !isToolbarVisible {
                VStack {
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isToolbarVisible = true
                                isActionBarVisible = true
                            }
                        }) {
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                        .padding(.top, 16)
                    }
                    
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(
            color: .black.opacity(UserDefaults.standard.bool(forKey: "floatingWindowShowShadow") ? 0.3 : 0),
            radius: UserDefaults.standard.bool(forKey: "floatingWindowShowShadow") ? 20 : 0,
            x: 0,
            y: UserDefaults.standard.bool(forKey: "floatingWindowShowShadow") ? 10 : 0
        )
        .opacity(UserDefaults.standard.double(forKey: "floatingWindowOpacity"))
        .onAppear {
            // 应用用户设置
            updateWindowAppearance()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            // 监听设置变化
            updateWindowAppearance()
        }
    }
    
    private func updateWindowAppearance() {
        // 这里可以添加更多外观更新逻辑
        // 由于SwiftUI的限制，一些设置需要在NSWindow层面处理
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

// MARK: - Editing Toolbar
struct EditingToolbar: View {
    @Binding var selectedTool: EditingTool
    @Binding var selectedColor: Color
    @Binding var lineWidth: CGFloat
    @Binding var showingColorPicker: Bool
    let onToolSelected: (EditingTool) -> Void
    
    private let colors: [Color] = [
        .red, .blue, .green, .yellow, .orange, .purple, .pink, .black, .white, .gray
    ]
    
    var body: some View {
        HStack(spacing: 12) {
            // 工具选择
            HStack(spacing: 8) {
                ForEach(EditingTool.allCases, id: \.self) { tool in
                    ToolButton(
                        tool: tool,
                        isSelected: selectedTool == tool,
                        action: {
                            selectedTool = tool
                            onToolSelected(tool)
                        }
                    )
                }
            }
            
            Divider()
                .frame(height: 20)
            
            // 颜色选择
            HStack(spacing: 6) {
                Text("颜色:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(action: { showingColorPicker.toggle() }) {
                    Circle()
                        .fill(selectedColor)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingColorPicker) {
                    ColorPickerView(selectedColor: $selectedColor)
                        .padding()
                }
                
                // 快速颜色选择
                HStack(spacing: 4) {
                    ForEach(colors, id: \.self) { color in
                        Button(action: { selectedColor = color }) {
                            Circle()
                                .fill(color)
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle()
                                        .stroke(selectedColor == color ? Color.blue : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Divider()
                .frame(height: 20)
            
            // 线条粗细
            if selectedTool == .pen || selectedTool == .highlighter {
                HStack(spacing: 6) {
                    Text("粗细:")
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
            
            Spacer()
        }
    }
}

// MARK: - Tool Button
struct ToolButton: View {
    let tool: EditingTool
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tool.icon)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text(tool.name)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white : .secondary)
            }
            .frame(width: 50, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.blue : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Color Picker View
struct ColorPickerView: View {
    @Binding var selectedColor: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Text("选择颜色")
                .font(.headline)
            
            ColorPicker("", selection: $selectedColor, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 200, height: 100)
        }
        .frame(width: 220, height: 140)
    }
}

// MARK: - Image Editing Canvas
struct ImageEditingCanvas: View {
    let image: NSImage
    @ObservedObject var editingSession: ImageEditingSession
    let selectedTool: EditingTool
    let selectedColor: Color
    let lineWidth: CGFloat
    let canvasSize: CGSize
    
    @State private var currentPoints: [CGPoint] = []
    @State private var currentRect: CGRect = .zero
    @State private var isDragging = false
    @State private var startPoint: CGPoint = .zero
    
    var body: some View {
        ZStack {
            // 背景图片
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipped()
            
            // 编辑层
            Canvas { context, size in
                // 绘制所有已完成的编辑操作
                for operation in editingSession.operations {
                    drawOperation(operation, in: context, size: size)
                }
                
                // 绘制当前正在进行的操作
                drawCurrentOperation(in: context, size: size)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDragChanged(value)
                    }
                    .onEnded { value in
                        handleDragEnded(value)
                    }
            )
        }
        .onTapGesture(count: 2) {
            // 双击退出编辑模式
            if selectedTool != .none {
                // selectedTool = .none
            }
        }
    }
    
    private func handleDragChanged(_ value: DragGesture.Value) {
        switch selectedTool {
        case .pen, .highlighter:
            if !isDragging {
                currentPoints = [value.location]
                isDragging = true
            } else {
                currentPoints.append(value.location)
            }
            
        case .rectangle, .circle, .crop:
            if !isDragging {
                startPoint = value.location
                isDragging = true
            }
            currentRect = CGRect(
                x: min(startPoint.x, value.location.x),
                y: min(startPoint.y, value.location.y),
                width: abs(value.location.x - startPoint.x),
                height: abs(value.location.y - startPoint.y)
            )
            
        case .arrow:
            if !isDragging {
                currentPoints = [value.location]
                isDragging = true
            } else {
                if currentPoints.count == 1 {
                    currentPoints.append(value.location)
                } else {
                    currentPoints[1] = value.location
                }
            }
            
        case .mosaic:
            if !isDragging {
                startPoint = value.location
                isDragging = true
            }
            currentRect = CGRect(
                x: min(startPoint.x, value.location.x),
                y: min(startPoint.y, value.location.y),
                width: abs(value.location.x - startPoint.x),
                height: abs(value.location.y - startPoint.y)
            )
            
        default:
            break
        }
    }
    
    private func handleDragEnded(_ value: DragGesture.Value) {
        guard isDragging else { return }
        
        let operation: EditingOperation
        
        switch selectedTool {
        case .pen, .highlighter:
            operation = EditingOperation(
                type: selectedTool,
                points: currentPoints,
                color: NSColor(selectedColor),
                lineWidth: lineWidth
            )
            
        case .rectangle, .circle:
            operation = EditingOperation(
                type: selectedTool,
                points: [],
                color: NSColor(selectedColor),
                lineWidth: lineWidth,
                rect: currentRect
            )
            
        case .arrow:
            operation = EditingOperation(
                type: selectedTool,
                points: currentPoints,
                color: NSColor(selectedColor),
                lineWidth: lineWidth
            )
            
        case .mosaic:
            operation = EditingOperation(
                type: selectedTool,
                points: [],
                color: NSColor.gray,
                lineWidth: 1.0,
                rect: currentRect
            )
            
        default:
            isDragging = false
            currentPoints.removeAll()
            currentRect = .zero
            return
        }
        
        editingSession.addOperation(operation)
        
        // 重置状态
        isDragging = false
        currentPoints.removeAll()
        currentRect = .zero
    }
    
    private func drawOperation(_ operation: EditingOperation, in context: GraphicsContext, size: CGSize) {
        switch operation.type {
        case .pen, .highlighter:
            drawStroke(operation, in: context)
        case .rectangle:
            drawRectangle(operation, in: context)
        case .circle:
            drawCircle(operation, in: context)
        case .arrow:
            drawArrow(operation, in: context)
        case .mosaic:
            drawMosaic(operation, in: context)
        default:
            break
        }
    }
    
    private func drawCurrentOperation(in context: GraphicsContext, size: CGSize) {
        guard isDragging else { return }
        
        switch selectedTool {
        case .pen, .highlighter:
            if currentPoints.count > 1 {
                var path = Path()
                path.move(to: currentPoints[0])
                for point in currentPoints.dropFirst() {
                    path.addLine(to: point)
                }
                
                context.stroke(
                    path,
                    with: .color(selectedTool == .highlighter ? selectedColor.opacity(0.5) : selectedColor),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
            }
            
        case .rectangle:
            if currentRect.width > 0 && currentRect.height > 0 {
                let path = Path(currentRect)
                context.stroke(
                    path,
                    with: .color(selectedColor),
                    style: StrokeStyle(lineWidth: lineWidth)
                )
            }
            
        case .circle:
            if currentRect.width > 0 && currentRect.height > 0 {
                let path = Path(ellipseIn: currentRect)
                context.stroke(
                    path,
                    with: .color(selectedColor),
                    style: StrokeStyle(lineWidth: lineWidth)
                )
            }
            
        case .arrow:
            if currentPoints.count == 2 {
                drawArrowPreview(from: currentPoints[0], to: currentPoints[1], in: context)
            }
            
        case .mosaic:
            if currentRect.width > 0 && currentRect.height > 0 {
                let path = Path(currentRect)
                context.stroke(
                    path,
                    with: .color(.gray),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                )
            }
            
        default:
            break
        }
    }
    
    private func drawStroke(_ operation: EditingOperation, in context: GraphicsContext) {
        guard operation.points.count > 1 else { return }
        
        var path = Path()
        path.move(to: operation.points[0])
        for point in operation.points.dropFirst() {
            path.addLine(to: point)
        }
        
        let color = operation.type == .highlighter ? 
            operation.color.color.opacity(0.5) : operation.color.color
        
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: operation.lineWidth, lineCap: .round, lineJoin: .round)
        )
    }
    
    private func drawRectangle(_ operation: EditingOperation, in context: GraphicsContext) {
        guard let rect = operation.rect else { return }
        
        let path = Path(rect)
        context.stroke(
            path,
            with: .color(operation.color.color),
            style: StrokeStyle(lineWidth: operation.lineWidth)
        )
    }
    
    private func drawCircle(_ operation: EditingOperation, in context: GraphicsContext) {
        guard let rect = operation.rect else { return }
        
        let path = Path(ellipseIn: rect)
        context.stroke(
            path,
            with: .color(operation.color.color),
            style: StrokeStyle(lineWidth: operation.lineWidth)
        )
    }
    
    private func drawArrow(_ operation: EditingOperation, in context: GraphicsContext) {
        guard operation.points.count >= 2 else { return }
        
        let start = operation.points[0]
        let end = operation.points[1]
        
        drawArrowPreview(from: start, to: end, in: context, color: operation.color.color, lineWidth: operation.lineWidth)
    }
    
    private func drawArrowPreview(from start: CGPoint, to end: CGPoint, in context: GraphicsContext, color: Color = .red, lineWidth: CGFloat = 2.0) {
        // 绘制箭头线
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
        
        // 绘制箭头头部
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 15
        let arrowAngle: CGFloat = .pi / 6
        
        var arrowPath = Path()
        arrowPath.move(to: end)
        arrowPath.addLine(to: CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        ))
        arrowPath.move(to: end)
        arrowPath.addLine(to: CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        ))
        
        context.stroke(
            arrowPath,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
    }
    
    private func drawMosaic(_ operation: EditingOperation, in context: GraphicsContext) {
        guard let rect = operation.rect else { return }
        
        let mosaicSize: CGFloat = 8
        
        for x in stride(from: rect.minX, to: rect.maxX, by: mosaicSize) {
            for y in stride(from: rect.minY, to: rect.maxY, by: mosaicSize) {
                let blockRect = CGRect(x: x, y: y, width: mosaicSize, height: mosaicSize)
                let grayValue = Double.random(in: 0.3...0.7)
                let blockColor = Color(white: grayValue)
                
                context.fill(Path(blockRect), with: .color(blockColor))
            }
        }
    }
}

// MARK: - Quick Action Bar
struct QuickActionBar: View {
    let onSave: () -> Void
    let onCopy: () -> Void
    let onShare: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onClear: () -> Void
    let onClose: () -> Void
    
    let canUndo: Bool
    let canRedo: Bool
    let hasOperations: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // 编辑操作
            HStack(spacing: 8) {
                ActionButton(
                    icon: "arrow.uturn.backward",
                    title: "撤销",
                    action: onUndo,
                    isEnabled: canUndo
                )
                
                ActionButton(
                    icon: "arrow.uturn.forward",
                    title: "重做",
                    action: onRedo,
                    isEnabled: canRedo
                )
                
                ActionButton(
                    icon: "trash",
                    title: "清除",
                    action: onClear,
                    isEnabled: hasOperations
                )
            }
            
            Spacer()
            
            // 主要操作
            HStack(spacing: 8) {
                ActionButton(
                    icon: "doc.on.clipboard",
                    title: "复制",
                    action: onCopy,
                    style: .bordered
                )
                
                ActionButton(
                    icon: "square.and.arrow.up",
                    title: "分享",
                    action: onShare,
                    style: .bordered
                )
                
                ActionButton(
                    icon: "square.and.arrow.down",
                    title: "保存",
                    action: onSave,
                    style: .borderedProminent
                )
                
                ActionButton(
                    icon: "xmark",
                    title: "关闭",
                    action: onClose,
                    style: .bordered
                )
            }
        }
    }
}

// MARK: - Action Button
struct ActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    var isEnabled: Bool = true
    var style: ButtonStyle = .plain
    
    enum ButtonStyle {
        case plain
        case bordered
        case borderedProminent
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .disabled(!isEnabled)
        .modifier(ButtonStyleModifier(style: style))
    }
}

// MARK: - Button Style Modifier
struct ButtonStyleModifier: ViewModifier {
    let style: ActionButton.ButtonStyle
    
    func body(content: Content) -> some View {
        switch style {
        case .plain:
            content.buttonStyle(.plain)
        case .bordered:
            content.buttonStyle(.bordered)
        case .borderedProminent:
            content.buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Button Style Wrapper
struct AnyButtonStyle: ButtonStyle {
    private let _makeBody: (Configuration) -> AnyView
    
    init<S: ButtonStyle>(_ style: S) {
        _makeBody = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }
    
    func makeBody(configuration: Configuration) -> some View {
        _makeBody(configuration)
    }
}

#Preview {
    FloatingWindowContentView(
        screenshot: NSImage(systemSymbolName: "photo", accessibilityDescription: nil) ?? NSImage(),
        editingSession: ImageEditingSession(originalImage: NSImage()),
        onSave: { _ in },
        onCopy: { _ in },
        onShare: { _ in },
        onClose: { }
    )
    .frame(width: 600, height: 500)
}