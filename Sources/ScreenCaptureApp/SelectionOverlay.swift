import AppKit

final class SelectionOverlay: NSWindowController {
    private let selectionView: SelectionView
    private let completion: (CGRect?) -> Void

    init(screen: NSScreen, completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
        self.selectionView = SelectionView()

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = selectionView

        super.init(window: window)

        selectionView.onFinish = { [weak self] rect in
            self?.finish(rect)
        }
        selectionView.onCancel = { [weak self] in
            self?.finish(nil)
        }
    }

    required init?(coder: NSCoder) {
        preconditionFailure("SelectionOverlay does not support storyboards")
    }

    func begin() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish(_ rect: CGRect?) {
        close()
        completion(rect)
    }
}

final class SelectionView: NSView {
    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private let minimumSize: CGFloat = 16

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()

        guard let rect = selectionRect else {
            drawHint("Drag to select a recording area. Esc cancels.")
            return
        }

        NSColor.clear.setFill()
        rect.fill(using: .clear)

        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()

        drawSizeLabel(for: rect)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let rect = selectionRect, rect.width >= minimumSize, rect.height >= minimumSize else {
            reset()
            return
        }

        onFinish?(window?.convertToScreen(rect) ?? rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else {
            return nil
        }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }

    private func reset() {
        startPoint = nil
        currentPoint = nil
        needsDisplay = true
    }

    private func drawHint(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width)) x \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.65)
        ]
        text.draw(at: CGPoint(x: rect.minX + 8, y: min(bounds.maxY - 24, rect.maxY + 8)), withAttributes: attributes)
    }
}
