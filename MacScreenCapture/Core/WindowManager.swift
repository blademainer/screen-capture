import Foundation
import SwiftUI
import Cocoa
import Combine

// MARK: - Editing Window Manager (临时放在这里解决编译问题)
class EditingWindowManager: ObservableObject {
    static let shared = EditingWindowManager()
    
    @Published var activeWindows: [EditingWindowController] = []
    
    private init() {}
    
    func openEditingWindow(for image: NSImage, at position: CGPoint? = nil) {
        DispatchQueue.main.async { [weak self] in
            let editingWindow = EditingWindowController(screenshot: image)
            
            if let position = position {
                editingWindow.window?.setFrameOrigin(position)
            } else {
                self?.positionNewWindow(editingWindow.window)
            }
            
            editingWindow.showWindow(nil)
            editingWindow.window?.makeKeyAndOrderFront(nil)
            
            self?.activeWindows.append(editingWindow)
            
            editingWindow.onWindowClose = { [weak self] controller in
                self?.removeWindow(controller)
            }
            
            if UserDefaults.standard.bool(forKey: "autoCopyToClipboard") {
                self?.copyToClipboard(image)
            }
        }
    }
    
    private func positionNewWindow(_ window: NSWindow?) {
        guard let window = window else { return }
        
        if activeWindows.isEmpty {
            window.center()
        } else {
            let offset: CGFloat = 40
            let baseFrame = activeWindows.first?.window?.frame ?? window.frame
            let newOrigin = CGPoint(
                x: baseFrame.origin.x + offset * CGFloat(activeWindows.count),
                y: baseFrame.origin.y - offset * CGFloat(activeWindows.count)
            )
            window.setFrameOrigin(newOrigin)
            
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                var frame = window.frame
                
                if frame.maxX > screenFrame.maxX {
                    frame.origin.x = screenFrame.maxX - frame.width
                }
                if frame.minY < screenFrame.minY {
                    frame.origin.y = screenFrame.minY
                }
                
                window.setFrame(frame, display: true)
            }
        }
    }
    
    private func removeWindow(_ controller: EditingWindowController) {
        activeWindows.removeAll { $0 === controller }
    }
    
    private func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        
        let notification = NSUserNotification()
        notification.title = "MacScreenCapture"
        notification.informativeText = "截图已自动复制到剪贴板"
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    func closeAllWindows() {
        for controller in activeWindows {
            controller.close()
        }
        activeWindows.removeAll()
    }
    
    func minimizeAllWindows() {
        for controller in activeWindows {
            controller.window?.miniaturize(nil)
        }
    }
    
    func restoreAllWindows() {
        for controller in activeWindows {
            if controller.window?.isMiniaturized == true {
                controller.window?.deminiaturize(nil)
            }
        }
    }
    
    var hasActiveWindows: Bool {
        return !activeWindows.isEmpty
    }
    
    var activeWindowCount: Int {
        return activeWindows.count
    }
}

// MARK: - Editing Window Controller (临时放在这里解决编译问题)
class EditingWindowController: NSWindowController {
    private var screenshot: NSImage
    private var editingSession: ImageEditingSession
    var onWindowClose: ((EditingWindowController) -> Void)?
    
    init(screenshot: NSImage) {
        self.screenshot = screenshot
        self.editingSession = ImageEditingSession(originalImage: screenshot)
        
        let imageSize = screenshot.size
        let maxSize = CGSize(width: 900, height: 700)
        let aspectRatio = imageSize.width / imageSize.height
        
        var windowSize = imageSize
        if windowSize.width > maxSize.width {
            windowSize.width = maxSize.width
            windowSize.height = windowSize.width / aspectRatio
        }
        if windowSize.height > maxSize.height {
            windowSize.height = maxSize.height
            windowSize.width = windowSize.height * aspectRatio
        }
        
        windowSize.height += 140
        windowSize.width = max(windowSize.width, 500)
        
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        setupWindow()
        setupContent()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupWindow() {
        guard let window = window else { return }
        
        window.title = "图片编辑"
        window.level = .normal
        window.backgroundColor = NSColor.windowBackgroundColor
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        
        window.hasShadow = true
        window.isOpaque = true
        
        window.center()
        
        window.minSize = NSSize(width: 500, height: 400)
        
        window.animationBehavior = .documentWindow
        
        window.delegate = self
        
        window.collectionBehavior = [.managed, .participatesInCycle]
        
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }
    }
    
    private func setupContent() {
        // 使用简化的内容视图，避免复杂的依赖
        let hostingView = NSHostingView(rootView: 
            VStack {
                Text("图片编辑窗口")
                    .font(.title)
                    .padding()
                
                Image(nsImage: screenshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 400, maxHeight: 300)
                
                HStack {
                    Button("保存") {
                        // 保存功能
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("复制") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.writeObjects([self.screenshot])
                    }
                    .buttonStyle(.bordered)
                    
                    Button("关闭") {
                        self.close()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .padding()
        )
        
        window?.contentView = hostingView
    }
}

extension EditingWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onWindowClose?(self)
    }
}

// MARK: - Capture State
enum CaptureState: Equatable {
    case idle
    case screenshotting
    case recording(startTime: Date)
    case paused(duration: TimeInterval)
    
    var description: String {
        switch self {
        case .idle:
            return "空闲"
        case .screenshotting:
            return "截图中..."
        case .recording(let startTime):
            let duration = Date().timeIntervalSince(startTime)
            return "录制中 - \(formatDuration(duration))"
        case .paused(let duration):
            return "已暂停 - \(formatDuration(duration))"
        }
    }
}

// MARK: - Window Manager
@available(macOS 12.3, *)
class WindowManager: ObservableObject {
    static let shared = WindowManager()
    
    @Published var isMainWindowVisible = true
    @Published var captureState: CaptureState = .idle
    
    private var statusBarItem: NSStatusItem?
    private var statusBarMenu: NSMenu?
    private var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var recordingTimer: Timer?
    
    private init() {
        setupStatusBar()
        observeCaptureState()
    }
    
    deinit {
        recordingTimer?.invalidate()
        if let statusBarItem = statusBarItem {
            NSStatusBar.system.removeStatusItem(statusBarItem)
        }
    }
    
    // MARK: - Status Bar Setup
    private func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let statusBarItem = statusBarItem else { return }
        
        if let button = statusBarItem.button {
            button.image = NSImage(systemSymbolName: "camera", accessibilityDescription: "MacScreenCapture")
            button.target = self
            button.action = #selector(statusBarButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        setupStatusBarMenu()
    }
    
    private func setupStatusBarMenu() {
        statusBarMenu = NSMenu()
        
        // 主窗口控制
        let showWindowItem = NSMenuItem(
            title: "显示主窗口",
            action: #selector(showMainWindow),
            keyEquivalent: ""
        )
        showWindowItem.target = self
        
        let hideWindowItem = NSMenuItem(
            title: "隐藏主窗口",
            action: #selector(hideMainWindow),
            keyEquivalent: ""
        )
        hideWindowItem.target = self
        
        // 快速操作
        let quickCaptureItem = NSMenuItem(
            title: "快速截图",
            action: #selector(quickCapture),
            keyEquivalent: ""
        )
        quickCaptureItem.target = self
        
        let recordingItem = NSMenuItem(
            title: "开始录制",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        recordingItem.target = self
        
        // 设置和退出
        let settingsItem = NSMenuItem(
            title: "设置",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        
        let quitItem = NSMenuItem(
            title: "退出 MacScreenCapture",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        
        // 添加菜单项
        statusBarMenu?.addItem(showWindowItem)
        statusBarMenu?.addItem(hideWindowItem)
        statusBarMenu?.addItem(NSMenuItem.separator())
        statusBarMenu?.addItem(quickCaptureItem)
        statusBarMenu?.addItem(recordingItem)
        statusBarMenu?.addItem(NSMenuItem.separator())
        statusBarMenu?.addItem(settingsItem)
        statusBarMenu?.addItem(NSMenuItem.separator())
        statusBarMenu?.addItem(quitItem)
        
        statusBarItem?.menu = statusBarMenu
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            // 右键显示菜单
            statusBarItem?.menu = statusBarMenu
            statusBarItem?.button?.performClick(nil)
        } else {
            // 左键快速操作
            handleQuickAction()
        }
    }
    
    private func handleQuickAction() {
        switch captureState {
        case .idle:
            // 空闲时显示/隐藏主窗口
            if isMainWindowVisible {
                hideMainWindow()
            } else {
                showMainWindow()
            }
        case .recording:
            // 录制时停止录制
            Task { @MainActor in
                await CaptureManager.shared.stopRecording()
            }
        case .screenshotting:
            // 截图时不做操作
            break
        case .paused:
            // 暂停时恢复录制
            Task { @MainActor in
                await CaptureManager.shared.resumeRecording()
            }
        }
    }
    
    // MARK: - State Observation
    private func observeCaptureState() {
        $captureState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateStatusBarForState(state)
                self?.handleWindowVisibilityForState(state)
                self?.updateMenuForState(state)
            }
            .store(in: &cancellables)
    }
    
    private func updateStatusBarForState(_ state: CaptureState) {
        guard let button = statusBarItem?.button else { return }
        
        switch state {
        case .idle:
            button.image = NSImage(systemSymbolName: "camera", accessibilityDescription: "MacScreenCapture")
            button.toolTip = "MacScreenCapture - 空闲\n左键：显示/隐藏窗口\n右键：更多选项"
            stopRecordingTimer()
            
        case .screenshotting:
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "截图中")
            button.toolTip = "正在截图..."
            
        case .recording(let startTime):
            button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "录制中")
            let duration = Date().timeIntervalSince(startTime)
            button.toolTip = "录制中 - \(formatDuration(duration))\n左键：停止录制"
            startRecordingTimer(startTime: startTime)
            
        case .paused(let duration):
            button.image = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "已暂停")
            button.toolTip = "录制已暂停 - \(formatDuration(duration))\n左键：恢复录制"
            stopRecordingTimer()
        }
    }
    
    private func updateMenuForState(_ state: CaptureState) {
        guard let menu = statusBarMenu else { return }
        
        // 更新录制菜单项
        if let recordingItem = menu.item(withTitle: "开始录制") ?? menu.item(withTitle: "停止录制") ?? menu.item(withTitle: "恢复录制") {
            switch state {
            case .idle, .screenshotting:
                recordingItem.title = "开始录制"
                recordingItem.action = #selector(toggleRecording)
            case .recording:
                recordingItem.title = "停止录制"
                recordingItem.action = #selector(toggleRecording)
            case .paused:
                recordingItem.title = "恢复录制"
                recordingItem.action = #selector(toggleRecording)
            }
        }
        
        // 更新窗口控制菜单项的可用性
        menu.item(withTitle: "显示主窗口")?.isEnabled = !isMainWindowVisible
        menu.item(withTitle: "隐藏主窗口")?.isEnabled = isMainWindowVisible
    }
    
    private func handleWindowVisibilityForState(_ state: CaptureState) {
        switch state {
        case .screenshotting, .recording:
            // 截图或录制时自动隐藏主窗口
            if isMainWindowVisible && UserDefaults.standard.bool(forKey: "autoHideWindowDuringCapture") {
                hideMainWindow()
            }
        case .idle:
            // 截图完成后根据设置决定是否自动显示窗口
            if UserDefaults.standard.bool(forKey: "autoShowWindowAfterCapture") && !isMainWindowVisible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.showMainWindow()
                }
            }
        case .paused:
            break // 暂停时保持当前状态
        }
    }
    
    // MARK: - Recording Timer
    private func startRecordingTimer(startTime: Date) {
        stopRecordingTimer()
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if case .recording = self.captureState {
                    let duration = Date().timeIntervalSince(startTime)
                    self.statusBarItem?.button?.toolTip = "录制中 - \(formatDuration(duration))\n左键：停止录制"
                }
            }
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    // MARK: - Window Management
    func setMainWindow(_ window: NSWindow) {
        mainWindow = window
    }
    
    @objc private func showMainWindow() {
        guard let window = mainWindow else {
            // 如果没有主窗口引用，尝试激活应用
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        isMainWindowVisible = true
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // 确保窗口在屏幕可见区域内
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
            window.center()
        }
    }
    
    @objc private func hideMainWindow() {
        guard let window = mainWindow else { return }
        
        isMainWindowVisible = false
        window.orderOut(nil)
        
        // 设置为辅助应用，不在 Dock 中显示但保持运行
        NSApp.setActivationPolicy(.accessory)
    }
    
    // MARK: - Menu Actions
    @objc private func quickCapture() {
        Task { @MainActor in
            await CaptureManager.shared.captureRegion()
        }
    }
    
    @objc private func toggleRecording() {
        Task { @MainActor in
            let captureManager = CaptureManager.shared
            
            switch captureState {
            case .idle, .screenshotting:
                do {
                    try await captureManager.startRecording()
                } catch {
                    print("开始录制失败: \(error)")
                }
            case .recording:
                await captureManager.stopRecording()
            case .paused:
                await captureManager.resumeRecording()
            }
        }
    }
    
    @objc private func openSettings() {
        showMainWindow()
        
        // 发送通知切换到设置页面
        NotificationCenter.default.post(name: .showSettings, object: nil)
    }
    
    @objc private func quitApplication() {
        // 清理资源
        recordingTimer?.invalidate()
        
        // 如果正在录制，先停止录制
        if case .recording = captureState {
            Task { @MainActor in
                await CaptureManager.shared.stopRecording()
                
                // 延迟退出，确保录制完成
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NSApp.terminate(nil)
                }
            }
        } else {
            NSApp.terminate(nil)
        }
    }
    
    // MARK: - Public Methods
    func updateCaptureState(_ state: CaptureState) {
        DispatchQueue.main.async {
            self.captureState = state
        }
    }
    
    func showEditingWindow(for image: NSImage) {
        // 使用新的EditingWindowManager来管理编辑窗口
        EditingWindowManager.shared.openEditingWindow(for: image)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let showSettings = Notification.Name("showSettings")
}

// MARK: - Duration Formatting
func formatDuration(_ duration: TimeInterval) -> String {
    let hours = Int(duration) / 3600
    let minutes = Int(duration) % 3600 / 60
    let seconds = Int(duration) % 60
    
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - UserDefaults Keys
extension UserDefaults {
    private enum Keys {
        static let autoHideWindowDuringCapture = "autoHideWindowDuringCapture"
        static let autoShowWindowAfterCapture = "autoShowWindowAfterCapture"
    }
    
    var autoHideWindowDuringCapture: Bool {
        get { bool(forKey: Keys.autoHideWindowDuringCapture) }
        set { set(newValue, forKey: Keys.autoHideWindowDuringCapture) }
    }
    
    var autoShowWindowAfterCapture: Bool {
        get { bool(forKey: Keys.autoShowWindowAfterCapture) }
        set { set(newValue, forKey: Keys.autoShowWindowAfterCapture) }
    }
}