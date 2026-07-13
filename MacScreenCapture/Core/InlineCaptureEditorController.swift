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

    func replaceImage(_ image: NSImage) {
        editingSession.replaceOriginalImage(image)
    }
}

@MainActor
final class InlineCaptureEditorController: NSObject {
    private var context: CapturedRegionContext
    private let mapper: CaptureCoordinateMapper
    let model: InlineCaptureEditorModel
    private let recaptureSelection: (CGRect, [DisplayCoordinateSpace]) async throws -> NSImage
    private let completion: (InlineCaptureEditorOutcome) -> Void

    private var backdropWindows: [NSWindow] = []
    private var segmentWindows: [NSWindow] = []
    private var toolbarWindow: NSWindow?
    private var eventMonitor: Any?
    private var didComplete = false
    private var currentCaptureRect: CGRect
    private var selectionInteraction: SelectionInteraction?
    private var isRecapturing = false

    private struct SelectionInteraction {
        let initialRect: CGRect
        let startScreenPoint: CGPoint
        let handle: CaptureResizeHandle?
    }

    init(
        context: CapturedRegionContext,
        recaptureSelection: @escaping (CGRect, [DisplayCoordinateSpace]) async throws -> NSImage,
        completion: @escaping (InlineCaptureEditorOutcome) -> Void
    ) {
        self.context = context
        mapper = CaptureCoordinateMapper(spaces: context.coordinateSpaces)
        model = InlineCaptureEditorModel(image: context.image)
        currentCaptureRect = context.captureRect
        self.recaptureSelection = recaptureSelection
        self.completion = completion
        super.init()
    }

    func show() {
        createBackdropWindows()
        createSegmentWindows()
        createToolbarWindow()
        startEventMonitoring()

        orderEditorWindowsFront()
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
        segmentWindows = mapper.screenSegments(for: currentCaptureRect).map { segment in
            let window = makeWindow(frame: segment.screenRect, level: level, ignoresMouseEvents: false)
            let contentView = InlineCaptureSegmentView(
                frame: NSRect(origin: .zero, size: segment.screenRect.size),
                model: model,
                segment: segment,
                selectionSize: currentCaptureRect.size
            )
            contentView.interactionDelegate = self
            window.contentView = contentView
            ScreenshotGeometryDiagnostics.logInlineSegmentLayout(
                selectionCaptureRect: currentCaptureRect,
                displayID: segment.displayID,
                segmentCaptureRect: segment.captureRect,
                segmentScreenRect: segment.screenRect,
                canvasScreenRect: segment.screenRect,
                imageRect: segment.imageRect,
                imageSize: model.editingSession.currentImage.size
            )
            return window
        }
    }

    private func createToolbarWindow() {
        let segments = mapper.screenSegments(for: currentCaptureRect)
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
        ScreenshotGeometryDiagnostics.logInlineToolbarLayout(
            selectionCaptureRect: currentCaptureRect,
            anchorScreenRect: anchor.screenRect,
            toolbarFrame: toolbarFrame,
            visibleFrame: visibleFrame
        )
        let level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        let window = makeToolbarWindow(frame: toolbarFrame, level: level)
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

    private func makeToolbarWindow(frame: CGRect, level: NSWindow.Level) -> NSPanel {
        let window = InlineCaptureToolbarPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = level
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.becomesKeyOnlyIfNeeded = true
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        return window
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
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .keyDown:
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
            case .leftMouseDragged:
                return self.updateSelectionInteraction(to: NSEvent.mouseLocation) ? nil : event
            case .leftMouseUp:
                return self.endSelectionInteraction() ? nil : event
            default:
                return event
            }
        }
    }

    private func updateSelectionInteraction(to screenPoint: CGPoint) -> Bool {
        guard let interaction = selectionInteraction else { return false }
        let captureDelta = CGPoint(
            x: screenPoint.x - interaction.startScreenPoint.x,
            y: interaction.startScreenPoint.y - screenPoint.y
        )
        let geometry = CaptureSelectionGeometry(
            initialRect: interaction.initialRect,
            bounds: mapper.captureBounds,
            minimumSize: CGSize(width: 24, height: 24)
        )
        let updatedRect = interaction.handle.map { geometry.resizing(handle: $0, by: captureDelta) }
            ?? geometry.moving(by: captureDelta)
        guard updatedRect != currentCaptureRect else { return true }
        currentCaptureRect = updatedRect
        rebuildSelectionWindows()
        return true
    }

    private func endSelectionInteraction() -> Bool {
        guard let interaction = selectionInteraction else { return false }
        selectionInteraction = nil
        guard currentCaptureRect != interaction.initialRect else { return true }
        Task { await recaptureCurrentSelection(fallbackRect: interaction.initialRect) }
        return true
    }

    private func recaptureCurrentSelection(fallbackRect: CGRect) async {
        guard !isRecapturing else { return }
        isRecapturing = true
        orderEditorWindowsOut()
        try? await Task.sleep(nanoseconds: 60_000_000)

        do {
            ScreenshotGeometryDiagnostics.logCaptureSelectedRegion(
                captureRect: currentCaptureRect,
                displayFrames: context.coordinateSpaces.map {
                    ScreenshotGeometryDiagnostics.DisplayFrame(
                        displayID: $0.displayID,
                        captureFrame: $0.captureFrame,
                        screenFrame: $0.screenFrame
                    )
                }
            )
            let image = try await recaptureSelection(currentCaptureRect, context.coordinateSpaces)
            context = CapturedRegionContext(
                image: image,
                captureRect: currentCaptureRect,
                coordinateSpaces: context.coordinateSpaces
            )
            model.replaceImage(image)
        } catch {
            currentCaptureRect = fallbackRect
            NSSound.beep()
        }

        rebuildSelectionWindows()
        orderEditorWindowsFront()
        segmentWindows.first?.makeKeyAndOrderFront(nil)
        isRecapturing = false
    }

    private func rebuildSelectionWindows() {
        closeSelectionWindows()
        createSegmentWindows()
        createToolbarWindow()
        segmentWindows.forEach { $0.orderFrontRegardless() }
        toolbarWindow?.orderFrontRegardless()
    }

    private func closeSelectionWindows() {
        let windows = segmentWindows + [toolbarWindow].compactMap { $0 }
        windows.forEach { window in
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        segmentWindows.removeAll()
        toolbarWindow = nil
    }

    private func orderEditorWindowsOut() {
        (backdropWindows + segmentWindows + [toolbarWindow].compactMap { $0 }).forEach { $0.orderOut(nil) }
    }

    private func orderEditorWindowsFront() {
        backdropWindows.forEach { $0.orderFrontRegardless() }
        segmentWindows.forEach { $0.orderFrontRegardless() }
        toolbarWindow?.orderFrontRegardless()
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

extension InlineCaptureEditorController: InlineCaptureSegmentViewDelegate {
    func inlineCaptureSegmentView(
        _ view: InlineCaptureSegmentView,
        beginInteractionAt screenPoint: CGPoint,
        handle: CaptureResizeHandle?
    ) {
        guard !isRecapturing else { return }
        selectionInteraction = SelectionInteraction(
            initialRect: currentCaptureRect,
            startScreenPoint: screenPoint,
            handle: handle
        )
    }
}

private final class InlineCaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class InlineCaptureToolbarPanel: NSPanel {
    override var canBecomeMain: Bool { false }
}
