import AppKit
import Combine

@MainActor
protocol InlineCaptureSegmentViewDelegate: AnyObject {
    func inlineCaptureSegmentView(
        _ view: InlineCaptureSegmentView,
        beginInteractionAt screenPoint: CGPoint,
        handle: CaptureResizeHandle?
    )
}

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
    weak var interactionDelegate: InlineCaptureSegmentViewDelegate?

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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for center in handleCenters().values {
            let handleRect = CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: handleRect).fill()
            NSColor.black.setStroke()
            let outline = NSBezierPath(ovalIn: handleRect)
            outline.lineWidth = 1
            outline.stroke()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if resizeHandle(at: point) != nil || model.selectedTool == .none {
            return self
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let localPoint = convert(event.locationInWindow, from: nil)
        interactionDelegate?.inlineCaptureSegmentView(
            self,
            beginInteractionAt: window.convertPoint(toScreen: event.locationInWindow),
            handle: resizeHandle(at: localPoint)
        )
    }

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
        needsDisplay = true
    }

    private func resizeHandle(at point: CGPoint) -> CaptureResizeHandle? {
        handleCenters().first { _, center in
            hypot(point.x - center.x, point.y - center.y) <= 9
        }?.key
    }

    private func handleCenters() -> [CaptureResizeHandle: CGPoint] {
        let left = -segment.imageRect.minX
        let right = selectionSize.width - segment.imageRect.minX
        let bottom = -segment.imageRect.minY
        let top = selectionSize.height - segment.imageRect.minY
        let midX = selectionSize.width / 2 - segment.imageRect.minX
        let midY = selectionSize.height / 2 - segment.imageRect.minY
        let candidates: [CaptureResizeHandle: CGPoint] = [
            .topLeft: CGPoint(x: left, y: top),
            .top: CGPoint(x: midX, y: top),
            .topRight: CGPoint(x: right, y: top),
            .right: CGPoint(x: right, y: midY),
            .bottomRight: CGPoint(x: right, y: bottom),
            .bottom: CGPoint(x: midX, y: bottom),
            .bottomLeft: CGPoint(x: left, y: bottom),
            .left: CGPoint(x: left, y: midY)
        ]
        let hitBounds = bounds.insetBy(dx: -1, dy: -1)
        return Dictionary(uniqueKeysWithValues: CaptureResizeHandle.allCases.compactMap { handle in
            guard let center = candidates[handle], hitBounds.contains(center) else { return nil }
            return (
                handle,
                CGPoint(
                    x: min(max(center.x, 4), max(4, bounds.maxX - 4)),
                    y: min(max(center.y, 4), max(4, bounds.maxY - 4))
                )
            )
        })
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
