import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ScreenRecordingServiceDelegate {
    private let preferences = AppPreferences.shared
    private let screenshotService = ScreenshotService()
    private let recordingService = ScreenRecordingService()

    private var statusItem: NSStatusItem?
    private var menu = NSMenu()
    private var stopRecordingItem: NSMenuItem?
    private var recordingStatusItem: NSMenuItem?
    private var startRecordingItems: [NSMenuItem] = []
    private var showCursorItem: NSMenuItem?
    private var openAfterCaptureItem: NSMenuItem?
    private var showRecordingClicksItem: NSMenuItem?
    private var outputFolderItem: NSMenuItem?
    private var openLastCaptureItem: NSMenuItem?
    private var timer: Timer?
    private var selectionOverlay: SelectionOverlay?
    private var pendingQuit = false
    private var lastCaptureURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserNotifier.shared.requestAuthorization()
        recordingService.delegate = self
        configureStatusItem()
        rebuildMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        recordingService.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screen Capture")
        item.button?.image?.isTemplate = true
        item.menu = menu
        statusItem = item
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let title = NSMenuItem(title: "Screen Capture", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        menu.addItem(menuItem("Full Screenshot", action: #selector(captureFullScreen), key: "1"))
        menu.addItem(menuItem("Full Screenshot in 5 Seconds", action: #selector(captureDelayedFullScreen), key: ""))
        menu.addItem(menuItem("Select Area Screenshot", action: #selector(captureArea), key: "2"))
        menu.addItem(menuItem("Window Screenshot", action: #selector(captureWindow), key: "3"))
        menu.addItem(menuItem("Copy Full Screen to Clipboard", action: #selector(captureClipboardFullScreen), key: "4"))
        menu.addItem(menuItem("Copy Area to Clipboard", action: #selector(captureClipboardArea), key: ""))
        menu.addItem(menuItem("Copy Window to Clipboard", action: #selector(captureClipboardWindow), key: ""))

        menu.addItem(.separator())

        let fullRecording = menuItem("Start Full Screen Recording", action: #selector(startFullRecording), key: "5")
        let areaRecording = menuItem("Start Area Recording", action: #selector(startAreaRecording), key: "6")
        startRecordingItems = [fullRecording, areaRecording]
        menu.addItem(fullRecording)
        menu.addItem(areaRecording)

        let stopItem = menuItem("Stop Recording", action: #selector(stopRecording), key: ".")
        stopRecordingItem = stopItem
        menu.addItem(stopItem)

        let status = NSMenuItem(title: "Not Recording", action: nil, keyEquivalent: "")
        status.isEnabled = false
        recordingStatusItem = status
        menu.addItem(status)

        menu.addItem(.separator())

        let outputItem = menuItem("Save To: \(preferences.outputDirectory.path)", action: #selector(chooseOutputFolder), key: "")
        outputFolderItem = outputItem
        menu.addItem(outputItem)
        menu.addItem(menuItem("Open Save Folder", action: #selector(openOutputFolder), key: "o"))
        let lastItem = menuItem("Reveal Last Capture", action: #selector(openLastCapture), key: "l")
        openLastCaptureItem = lastItem
        menu.addItem(lastItem)

        menu.addItem(.separator())

        let cursor = menuItem("Show Cursor in Full Screenshot", action: #selector(toggleShowCursor), key: "")
        showCursorItem = cursor
        menu.addItem(cursor)

        let reveal = menuItem("Reveal File After Capture", action: #selector(toggleOpenAfterCapture), key: "")
        openAfterCaptureItem = reveal
        menu.addItem(reveal)

        let clicks = menuItem("Show Clicks in Recording", action: #selector(toggleShowRecordingClicks), key: "")
        showRecordingClicksItem = clicks
        menu.addItem(clicks)

        menu.addItem(.separator())
        menu.addItem(menuItem("Request Screen Permission", action: #selector(requestScreenPermission), key: "p"))
        menu.addItem(menuItem("Open Screen Recording Settings", action: #selector(openPermissionSettings), key: "s"))

        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Screen Capture", action: #selector(quit), key: "q"))

        updateMenuState()
    }

    private func menuItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func updateMenuState() {
        let isRecording = recordingService.isRecording
        stopRecordingItem?.isEnabled = isRecording
        startRecordingItems.forEach { $0.isEnabled = !isRecording }

        showCursorItem?.state = preferences.showCursor ? .on : .off
        openAfterCaptureItem?.state = preferences.openAfterCapture ? .on : .off
        showRecordingClicksItem?.state = preferences.showRecordingClicks ? .on : .off
        outputFolderItem?.title = "Save To: \(preferences.outputDirectory.path)"
        openLastCaptureItem?.isEnabled = lastCaptureURL != nil

        if isRecording, let startedAt = recordingService.startedAt {
            let modeName = recordingService.mode?.userFacingName ?? "Recording"
            recordingStatusItem?.title = "\(modeName) \(formatDuration(Date().timeIntervalSince(startedAt)))"
            stopRecordingItem?.title = recordingService.mode?.isSelectedArea == true ? "Stop Area Recording" : "Stop Recording"
            statusItem?.button?.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
        } else {
            recordingStatusItem?.title = "Not Recording"
            stopRecordingItem?.title = "Stop Recording"
            statusItem?.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screen Capture")
        }
        statusItem?.button?.image?.isTemplate = true
    }

    @objc private func captureFullScreen() {
        capture(.fullScreen, successMessage: "Screenshot saved")
    }

    @objc private func captureDelayedFullScreen() {
        capture(.fullScreenDelayed(seconds: 5), successMessage: "Timed screenshot saved")
    }

    @objc private func captureArea() {
        capture(.selectedArea, successMessage: "Screenshot saved")
    }

    @objc private func captureWindow() {
        capture(.selectedWindow, successMessage: "Window screenshot saved")
    }

    @objc private func captureClipboardArea() {
        capture(.clipboardArea, successMessage: "Screenshot copied to clipboard")
    }

    @objc private func captureClipboardFullScreen() {
        capture(.clipboardFullScreen, successMessage: "Screenshot copied to clipboard")
    }

    @objc private func captureClipboardWindow() {
        capture(.clipboardWindow, successMessage: "Window screenshot copied to clipboard")
    }

    private func capture(_ mode: ScreenshotMode, successMessage: String) {
        guard ensurePermission() else { return }
        screenshotService.capture(mode) { result in
            switch result {
            case .success(let url):
                if let url {
                    self.lastCaptureURL = url
                    self.updateMenuState()
                }
                UserNotifier.shared.success(title: "Screen Capture", message: successMessage, fileURL: url)
            case .failure(let error):
                if case CaptureError.cancelled = error {
                    UserNotifier.shared.info(title: "Screen Capture", message: "Capture cancelled")
                } else {
                    UserNotifier.shared.error(error)
                }
            }
        }
    }

    @objc private func startFullRecording() {
        startRecording(.fullScreen)
    }

    @objc private func startAreaRecording() {
        guard ensurePermission() else { return }
        let screen = screenForMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            UserNotifier.shared.error(CaptureError.noDisplay)
            return
        }

        selectionOverlay = SelectionOverlay(screen: screen) { [weak self] rect in
            guard let self else { return }
            self.selectionOverlay = nil
            guard let rect else {
                UserNotifier.shared.info(title: "Screen Capture", message: "Recording cancelled")
                return
            }
            self.startRecording(.selectedArea(rect))
        }
        selectionOverlay?.begin()
    }

    private func startRecording(_ mode: RecordingMode) {
        guard ensurePermission() else { return }

        recordingService.start(mode: mode)
        updateMenuState()
    }

    @objc private func stopRecording() {
        recordingService.stop()
        updateMenuState()
    }

    @objc private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = preferences.outputDirectory
        if panel.runModal() == .OK, let url = panel.url {
            preferences.outputDirectory = url
            updateMenuState()
        }
    }

    @objc private func openOutputFolder() {
        NSWorkspace.shared.open(preferences.outputDirectory)
    }

    @objc private func openLastCapture() {
        guard let lastCaptureURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastCaptureURL])
    }

    @objc private func toggleShowCursor() {
        preferences.showCursor.toggle()
        updateMenuState()
    }

    @objc private func toggleOpenAfterCapture() {
        preferences.openAfterCapture.toggle()
        updateMenuState()
    }

    @objc private func toggleShowRecordingClicks() {
        preferences.showRecordingClicks.toggle()
        updateMenuState()
    }

    @objc private func requestScreenPermission() {
        if PermissionService.requestScreenRecordingPermission() {
            UserNotifier.shared.success(title: "Screen Capture", message: "Screen Recording permission is already granted")
        } else {
            PermissionService.openPrivacySettings()
        }
    }

    @objc private func openPermissionSettings() {
        PermissionService.openPrivacySettings()
    }

    @objc private func quit() {
        if recordingService.isRecording {
            let alert = NSAlert()
            alert.messageText = "Recording in Progress"
            alert.informativeText = "Stop the current recording and quit after the video is saved?"
            alert.addButton(withTitle: "Stop and Quit")
            alert.addButton(withTitle: "Keep Recording")
            guard alert.runModal() == .alertFirstButtonReturn else {
                return
            }

            pendingQuit = true
            recordingService.stop()
            return
        }
        NSApp.terminate(nil)
    }

    private func ensurePermission() -> Bool {
        if PermissionService.hasScreenRecordingPermission {
            return true
        }

        if PermissionService.requestScreenRecordingPermission() {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "Grant Screen Capture access in System Settings, then restart the app if macOS asks for it."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            PermissionService.openPrivacySettings()
        }
        return false
    }

    private func screenForMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMenuState()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func recordingServiceDidStart(_ service: ScreenRecordingService, outputURL: URL) {
        startTimer()
        updateMenuState()
        let message = service.mode?.isSelectedArea == true
            ? "Area recording started"
            : "Recording started"
        UserNotifier.shared.info(title: "Screen Capture", message: message)
    }

    func recordingService(_ service: ScreenRecordingService, didFinishWith result: Result<URL, Error>) {
        stopTimer()
        updateMenuState()
        switch result {
        case .success(let url):
            lastCaptureURL = url
            updateMenuState()
            UserNotifier.shared.success(title: "Screen Capture", message: "Recording saved", fileURL: url)
        case .failure(let error):
            if case CaptureError.cancelled = error {
                UserNotifier.shared.info(title: "Screen Capture", message: "Recording cancelled")
            } else {
                UserNotifier.shared.error(error)
            }
        }

        if pendingQuit {
            pendingQuit = false
            NSApp.terminate(nil)
        }
    }

    func diagnosticMenuTitles() -> [String] {
        menu.items.map { item in
            item.isSeparatorItem ? "-" : item.title
        }
    }
}
