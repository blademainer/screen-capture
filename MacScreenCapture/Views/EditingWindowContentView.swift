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
        GeometryReader { geometry in
            let availableSize = availableEditingSurfaceSize(in: geometry.size)
            let frameSize = boundedEditingFrameSize(for: editingSession.currentImage.size, in: availableEditingSurfaceSize(in: geometry.size))

            ZStack {
                Color(NSColor(calibratedWhite: 0.18, alpha: 1))
                editorStack(frameSize: frameSize)
            }
            .onAppear {
                logEditorLayout(windowSize: geometry.size, availableSize: availableSize, frameSize: frameSize)
            }
            .onChange(of: geometry.size) { _, newWindowSize in
                let newAvailableSize = availableEditingSurfaceSize(in: newWindowSize)
                let newFrameSize = boundedEditingFrameSize(for: editingSession.currentImage.size, in: newAvailableSize)
                logEditorLayout(windowSize: newWindowSize, availableSize: newAvailableSize, frameSize: newFrameSize)
            }
            .onChange(of: editingSession.currentImage.size) { _, newImageSize in
                let newFrameSize = boundedEditingFrameSize(for: newImageSize, in: availableSize)
                logEditorLayout(windowSize: geometry.size, availableSize: availableSize, frameSize: newFrameSize)
            }
        }
        .background(Color(NSColor(calibratedWhite: 0.18, alpha: 1)))
        .onAppear {
            selectedColor = .annotationDefault(hex: annotationDefaultColorHex)
            lineWidth = CGFloat(annotationDefaultLineWidth)
            fontSize = CGFloat(annotationDefaultFontSize)
        }
    }

    private func logEditorLayout(windowSize: CGSize, availableSize: CGSize, frameSize: CGSize) {
        ScreenshotGeometryDiagnostics.logEditorLayout(
            imageSize: editingSession.currentImage.size,
            windowSize: windowSize,
            availableSize: availableSize,
            frameSize: frameSize,
            surfacePadding: 18
        )
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
    private func editorStack(frameSize: CGSize) -> some View {
        VStack(spacing: 0) {
            if isToolbarVisible {
                editingToolbar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(width: frameSize.width + 36)
                    .background(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(Color(NSColor.separatorColor)),
                        alignment: .bottom
                    )
            }

            editingSurface(size: frameSize)

            if isActionBarVisible {
                actionBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(width: frameSize.width + 36)
                    .background(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(Color(NSColor.separatorColor)),
                        alignment: .top
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 12, x: 0, y: 6)
    }

    private func editingSurface(size: CGSize) -> some View {
        ZStack {
            Color(NSColor.textBackgroundColor)

            Image(nsImage: editingSession.currentImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height)

            TraditionalEditingCanvas(
                editingSession: editingSession,
                selectedTool: selectedTool,
                selectedColor: selectedColor,
                lineWidth: lineWidth,
                fontSize: fontSize,
                textOutlined: textOutlined
            )
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .padding(18)
        .background(Color(NSColor.textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    private func availableEditingSurfaceSize(in windowSize: CGSize) -> CGSize {
        CGSize(
            width: windowSize.width,
            height: max(260, windowSize.height - 160)
        )
    }

    private func boundedEditingFrameSize(for imageSize: CGSize, in availableSize: CGSize) -> CGSize {
        let maxWidth = min(960, max(360, availableSize.width - 96))
        let maxHeight = min(680, max(260, availableSize.height - 96))
        let fallbackSize = CGSize(width: min(maxWidth, 700), height: min(maxHeight, 460))

        guard imageSize.width > 0, imageSize.height > 0 else {
            return fallbackSize
        }

        let aspectRatio = imageSize.width / imageSize.height
        var width = maxWidth
        var height = width / aspectRatio

        if height > maxHeight {
            height = maxHeight
            width = height * aspectRatio
        }

        return CGSize(
            width: max(240, min(width, maxWidth)),
            height: max(180, min(height, maxHeight))
        )
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
