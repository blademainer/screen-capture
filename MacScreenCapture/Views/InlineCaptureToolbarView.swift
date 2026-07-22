import SwiftUI

struct InlineCaptureToolbarView: View {
    @ObservedObject var model: InlineCaptureEditorModel

    let onSelectTool: (EditingTool) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onClear: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onPin: () -> Void
    let onOCR: () -> Void
    let onScrolling: () -> Void
    let onFinish: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(EditingTool.allCases, id: \.self) { tool in
                    Button {
                        onSelectTool(tool)
                    } label: {
                        Image(systemName: tool.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(model.selectedTool == tool ? Color.white : Color.primary)
                            .frame(width: 28, height: 28)
                            .background(model.selectedTool == tool ? Color.accentColor : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help(tool.name)
                }

                Divider().frame(height: 22)

                ColorPicker("", selection: colorBinding, supportsOpacity: true)
                    .labelsHidden()
                    .frame(width: 28, height: 28)
                    .help("标注颜色")

                toolbarButton("arrow.uturn.backward", help: "撤销", disabled: !model.editingSession.canUndo, action: onUndo)
                toolbarButton("arrow.uturn.forward", help: "重做", disabled: !model.editingSession.canRedo, action: onRedo)
                toolbarButton("trash", help: "清除标注", action: onClear)
            }

            HStack(spacing: 7) {
                Image(systemName: "line.diagonal")
                    .help("线条粗细")
                Slider(value: $model.lineWidth, in: 1...10, step: 1)
                    .frame(width: 82)

                Image(systemName: "textformat.size")
                    .help("文字大小")
                Slider(value: $model.fontSize, in: 10...72, step: 1)
                    .frame(width: 82)
                    .disabled(model.selectedTool != .text && model.selectedTool != .numbered)

                Divider().frame(height: 22)

                toolbarButton("doc.on.doc", help: "复制", action: onCopy)
                toolbarButton("square.and.arrow.down", help: "保存", action: onSave)
                toolbarButton("square.and.arrow.up", help: "分享", action: onShare)
                toolbarButton("pin", help: "贴图", action: onPin)
                toolbarButton("text.viewfinder", help: "OCR", action: onOCR)
                toolbarButton("rectangle.and.hand.point.up.left", help: "滚动截图", action: onScrolling)

                Divider().frame(height: 22)

                toolbarButton("xmark", help: "取消", action: onCancel)
                toolbarButton("checkmark", help: "完成", emphasized: true, action: onFinish)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 8, x: 0, y: 4)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: model.selectedColor) },
            set: { model.selectedColor = NSColor($0) }
        )
    }

    private func toolbarButton(
        _ systemName: String,
        help: String,
        disabled: Bool = false,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: emphasized ? .bold : .regular))
                .foregroundStyle(emphasized ? Color.white : Color.primary)
                .frame(width: 28, height: 28)
                .background(emphasized ? Color.accentColor : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }
}
