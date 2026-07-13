import AppKit
import Combine

final class InlineCaptureBackdropView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.48).setFill()
        bounds.fill()
    }
}

final class InlineCaptureSegmentView: NSView, FloatingEditingCanvasDelegate {
    private let model: InlineCaptureEditorModel
    private let segment: CaptureScreenSegment
    private let selectionSize: CGSize
    private let imageView = NSImageView()
    private let canvasView = FloatingEditingCanvasView()
    private var cancellables = Set<AnyCancellable>()

    init(
        frame frameRect: NSRect,
        model: InlineCaptureEditorModel,
        segment: CaptureScreenSegment,
        selectionSize: CGSize
    ) {
        self.model = model
        self.segment = segment
        self.selectionSize = selectionSize
        super.init(frame: frameRect)
        setupViews()
        observeModel()
        updateContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    private func setupViews() {
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.borderColor = NSColor.systemBlue.cgColor
        layer?.borderWidth = 2

        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageFrameStyle = .none
        imageView.animates = false

        canvasView.editingSession = model.editingSession
        canvasView.delegate = self
        canvasView.imageSize = model.editingSession.currentImage.size

        addSubview(imageView)
        addSubview(canvasView)
    }

    private func observeModel() {
        model.editingSession.$currentImage
            .receive(on: RunLoop.main)
            .sink { [weak self] image in
                self?.imageView.image = image
                self?.canvasView.imageSize = image.size
                self?.canvasView.needsDisplay = true
            }
            .store(in: &cancellables)

        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                DispatchQueue.main.async {
                    self?.updateCanvasConfiguration()
                }
            }
            .store(in: &cancellables)
    }

    private func updateContent() {
        let fullSelectionFrame = CGRect(
            x: -segment.imageRect.minX,
            y: -segment.imageRect.minY,
            width: selectionSize.width,
            height: selectionSize.height
        )
        imageView.frame = fullSelectionFrame
        canvasView.frame = fullSelectionFrame
        imageView.image = model.editingSession.currentImage
        updateCanvasConfiguration()
    }

    private func updateCanvasConfiguration() {
        canvasView.selectedTool = model.selectedTool
        canvasView.selectedColor = model.selectedColor
        canvasView.lineWidth = model.lineWidth
        canvasView.fontSize = model.fontSize
        canvasView.textOutlined = model.textOutlined
        canvasView.syncResetRevision(model.editingSession.resetRevision)
        canvasView.needsDisplay = true
    }

    func canvasDidAddOperation(_ operation: EditingOperation) {
        model.editingSession.addOperation(operation)
    }
}
