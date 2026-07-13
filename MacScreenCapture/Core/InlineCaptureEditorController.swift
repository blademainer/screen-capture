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
    private var editingSessionObservation: AnyCancellable?

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
        editingSessionObservation = editingSession.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
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
    private var toolbarWindow: NSWindow?
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
        createToolbarWindow()
        startEventMonitoring()

        backdropWindows.forEach { $0.orderFrontRegardless() }
        segmentWindows.forEach { $0.orderFrontRegardless() }
        toolbarWindow?.orderFrontRegardless()
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

    private func createToolbarWindow() {
        let segments = mapper.screenSegments(for: context.captureRect)
        guard let anchor = segments.max(by: { $0.screenRect.width * $0.screenRect.height < $1.screenRect.width * $1.screenRect.height }) else {
            return
        }

        let visibleFrame = screen(for: anchor.displayID)?.visibleFrame
            ?? context.coordinateSpaces.first(where: { $0.displayID == anchor.displayID })?.screenFrame
            ?? anchor.screenRect
        let toolbarSize = CGSize(width: min(760, max(320, visibleFrame.width - 16)), height: 92)
        let toolbarFrame = CaptureOverlayLayout.toolbarFrame(
            selection: anchor.screenRect,
            toolbarSize: toolbarSize,
            visibleFrame: visibleFrame
        )
        let level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        let window = makeWindow(frame: toolbarFrame, level: level, ignoresMouseEvents: false)
        window.hasShadow = true
        window.contentView = NSHostingView(rootView: InlineCaptureToolbarView(
            model: model,
            onUndo: { [weak self] in self?.model.editingSession.undo() },
            onRedo: { [weak self] in self?.model.editingSession.redo() },
            onClear: { [weak self] in self?.model.editingSession.clear() },
            onCopy: { [weak self] in self?.completeWithImage(.copy) },
            onSave: { [weak self] in self?.completeWithImage(.save) },
            onShare: { [weak self] in self?.share() },
            onPin: { [weak self] in self?.completeWithImage(.pin) },
            onOCR: { [weak self] in self?.completeWithImage(.ocr) },
            onScrolling: { [weak self] in self?.completeWithImage(.scrolling) },
            onFinish: { [weak self] in self?.finish() },
            onCancel: { [weak self] in self?.cancel() }
        ))
        toolbarWindow = window
    }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return number.uint32Value == displayID
        }
    }

    private enum ImageOutcome {
        case copy
        case save
        case pin
        case ocr
        case scrolling
    }

    private func completeWithImage(_ outcome: ImageOutcome) {
        let image = model.editingSession.currentImage
        switch outcome {
        case .copy: complete(.copy(image))
        case .save: complete(.save(image))
        case .pin: complete(.pin(image))
        case .ocr: complete(.ocr(image))
        case .scrolling: complete(.scrolling(image))
        }
    }

    private func share() {
        guard let contentView = toolbarWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [model.editingSession.currentImage])
        picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
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
        let windows = segmentWindows + backdropWindows + [toolbarWindow].compactMap { $0 }
        windows.forEach { window in
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        segmentWindows.removeAll()
        backdropWindows.removeAll()
        toolbarWindow = nil
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
