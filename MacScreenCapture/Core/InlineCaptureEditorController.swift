import AppKit
import Combine
import SwiftUI

enum InlineCaptureEditorOutcome {
    case finish(NSImage)
    case copy(NSImage)
    case save(NSImage)
    case pin(NSImage)
    case ocr(NSImage)
    case scrolling(NSImage)
    case cancel
}

final class InlineCaptureEditorModel: ObservableObject {
    let editingSession: ImageEditingSession

    @Published var selectedTool: EditingTool = .none
    @Published var selectedColor: NSColor
    @Published var lineWidth: CGFloat
    @Published var fontSize: CGFloat
    @Published var textOutlined: Bool

    init(image: NSImage) {
        editingSession = ImageEditingSession(originalImage: image)
        let defaults = UserDefaults.standard
        let colorHex = defaults.string(forKey: "annotationDefaultColorHex") ?? AnnotationStylePreset.professional.colorHex
        selectedColor = NSColor.annotationDefault(hex: colorHex) ?? .systemRed
        lineWidth = CGFloat(defaults.object(forKey: "annotationDefaultLineWidth") as? Double ?? AnnotationStylePreset.professional.lineWidth)
        fontSize = CGFloat(defaults.object(forKey: "annotationDefaultFontSize") as? Double ?? AnnotationStylePreset.professional.fontSize)
        textOutlined = UserDefaults.standard.bool(forKey: "annotationTextOutlined")
    }
}

@MainActor
final class InlineCaptureEditorController: NSObject {
    private let context: CapturedRegionContext
    private let mapper: CaptureCoordinateMapper
    let model: InlineCaptureEditorModel
    private let completion: (InlineCaptureEditorOutcome) -> Void

    private var backdropWindows: [NSWindow] = []
    private var segmentWindows: [NSWindow] = []
    private var eventMonitor: Any?
    private var didComplete = false

    init(
        context: CapturedRegionContext,
        completion: @escaping (InlineCaptureEditorOutcome) -> Void
    ) {
        self.context = context
        mapper = CaptureCoordinateMapper(spaces: context.coordinateSpaces)
        model = InlineCaptureEditorModel(image: context.image)
        self.completion = completion
        super.init()
    }

    func show() {
        createBackdropWindows()
        createSegmentWindows()
        startEventMonitoring()

        backdropWindows.forEach { $0.orderFrontRegardless() }
        segmentWindows.forEach { $0.orderFrontRegardless() }
        segmentWindows.first?.makeKeyAndOrderFront(nil)
        segmentWindows.first?.makeFirstResponder(segmentWindows.first?.contentView)
        NSApp.activate(ignoringOtherApps: true)
    }

    func finish() {
        complete(.finish(model.editingSession.currentImage))
    }

    func cancel() {
        complete(.cancel)
    }

    private func createBackdropWindows() {
        let level = NSWindow.Level.screenSaver
        backdropWindows = context.coordinateSpaces.map { space in
            let window = makeWindow(frame: space.screenFrame, level: level, ignoresMouseEvents: true)
            window.contentView = InlineCaptureBackdropView(frame: NSRect(origin: .zero, size: space.screenFrame.size))
            return window
        }
    }

    private func createSegmentWindows() {
        let level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        segmentWindows = mapper.screenSegments(for: context.captureRect).map { segment in
            let window = makeWindow(frame: segment.screenRect, level: level, ignoresMouseEvents: false)
            window.contentView = InlineCaptureSegmentView(
                frame: NSRect(origin: .zero, size: segment.screenRect.size),
                model: model,
                segment: segment,
                selectionSize: context.captureRect.size
            )
            return window
        }
    }

    private func makeWindow(
        frame: CGRect,
        level: NSWindow.Level,
        ignoresMouseEvents: Bool
    ) -> NSWindow {
        let window = InlineCaptureWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = level
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = ignoresMouseEvents
        window.acceptsMouseMovedEvents = !ignoresMouseEvents
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        return window
    }

    private func startEventMonitoring() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53:
                self.cancel()
                return nil
            case 36, 76:
                self.finish()
                return nil
            default:
                return event
            }
        }
    }

    private func complete(_ outcome: InlineCaptureEditorOutcome) {
        guard !didComplete else { return }
        didComplete = true
        closeWindows()
        completion(outcome)
    }

    private func closeWindows() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        (segmentWindows + backdropWindows).forEach { window in
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        segmentWindows.removeAll()
        backdropWindows.removeAll()
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}

private final class InlineCaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
