import SwiftUI
import Cocoa

struct EditingWindowContentView: View {
    let screenshot: NSImage
    @ObservedObject var editingSession: ImageEditingSession
    
    let onSave: (NSImage) -> Void
    let onCopy: (NSImage) -> Void
    let onShare: (NSImage) -> Void
    let onClear: () -> Void
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
        .onAppear {
            selectedColor = .annotationDefault(hex: annotationDefaultColorHex)
            lineWidth = CGFloat(annotationDefaultLineWidth)
            fontSize = CGFloat(annotationDefaultFontSize)
        }
    }
    
    // MARK: - Editing Toolbar
    private var editingToolbar: some View {
        HStack(spacing: 16) {
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
        GeometryReader { _ in
            ZStack {
                Color(NSColor(calibratedWhite: 0.18, alpha: 1))

                ZStack {
                    Color(NSColor.textBackgroundColor)

                    // 背景图片
                    Image(nsImage: editingSession.currentImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // 与贴图浮窗复用同一套增强编辑画布，保证普通截图编辑能力一致。
                    TraditionalEditingCanvas(
                        editingSession: editingSession,
                        selectedTool: selectedTool,
                        selectedColor: selectedColor,
                        lineWidth: lineWidth,
                        fontSize: fontSize,
                        textOutlined: textOutlined
                    )
                }
                .padding(18)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.22), radius: 12, x: 0, y: 6)
                .padding(28)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(Color(NSColor(calibratedWhite: 0.18, alpha: 1)))
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
            
            Button("清除", action: clearAllEdits)
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            
            Spacer()
            
            Button("退出", action: onClose)
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

    private func clearAllEdits() {
        selectedTool = .none
        isEditing = false
        onClear()
    }
    
    private func generateFinalImage() -> NSImage {
        editingSession.currentImage
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
        onClear: { },
        onClose: { }
    )
    .frame(width: 700, height: 600)
}
