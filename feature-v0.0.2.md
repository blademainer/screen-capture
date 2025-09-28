# v0.0.2功能规划

功能列表
1. 快捷键：支持用户自定义快捷键，实现一键截图、录屏等功能。
2. 滚动截屏：当截取应用程序时，支持自动对窗口内进行滚动，然后截取长图。
3. 截屏后置顶：当截屏后，将图片以浮窗的形式展示，且支持在浮窗内进行修改图片、复制、保存等操作，而不是在程序的小窗口内展示。
4. 截屏时自动隐藏主窗口：当启动截屏或录屏时，自动将截屏软件窗口隐藏，同时支持在状态栏显示截屏或录屏的图标，方便用户查看或停止截屏或录屏状态。

## 🔧 功能1: 快捷键支持

### 📝 功能描述
支持用户自定义快捷键，实现一键截图、录屏等功能，提供系统级全局快捷键监听。

### 🎯 用户需求

- 用户可以自定义快捷键组合，配置完成之后自动进行保存快捷键
- 支持全局快捷键（应用在后台时也能响应）
- 提供默认快捷键配置
- 快捷键冲突检测和提示

### 🏗 技术实现方案

#### 核心技术栈
```swift
import Carbon
import Cocoa
import SwiftUI
```

#### 架构设计
```
HotKeyManager (单例)
├── HotKeyRegistration (快捷键注册)
├── HotKeyConfiguration (配置管理)
├── HotKeyValidator (冲突检测)
└── HotKeyHandler (事件处理)
```

#### 详细实现逻辑

##### 1. HotKeyManager 核心类
```swift
class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()
    
    // 快捷键配置
    @Published var hotKeys: [HotKeyAction: HotKeyConfig] = [:]
    
    // 已注册的快捷键
    private var registeredHotKeys: [HotKeyAction: EventHotKeyRef] = [:]
    
    // 事件处理器
    private var eventHandler: EventHandlerRef?
    
    private init() {
        setupDefaultHotKeys()
        registerEventHandler()
    }
}
```

##### 2. 快捷键配置数据结构
```swift
struct HotKeyConfig: Codable {
    let keyCode: UInt32
    let modifiers: UInt32
    let isEnabled: Bool
    let description: String
    
    var displayString: String {
        // 将键码转换为用户友好的显示字符串
        // 例如: "⌘⇧S" 表示 Cmd+Shift+S
    }
}

enum HotKeyAction: String, CaseIterable {
    case fullScreenshot = "full_screenshot"
    case regionScreenshot = "region_screenshot"
    case windowScreenshot = "window_screenshot"
    case startRecording = "start_recording"
    case stopRecording = "stop_recording"
    case scrollScreenshot = "scroll_screenshot"
    
    var defaultConfig: HotKeyConfig {
        switch self {
        case .fullScreenshot:
            return HotKeyConfig(keyCode: 1, modifiers: cmdKey | shiftKey, isEnabled: true, description: "全屏截图")
        case .regionScreenshot:
            return HotKeyConfig(keyCode: 1, modifiers: cmdKey | shiftKey, isEnabled: true, description: "区域截图")
        // ... 其他默认配置
        }
    }
}
```

##### 3. 快捷键注册逻辑
```swift
extension HotKeyManager {
    func registerHotKey(_ action: HotKeyAction, config: HotKeyConfig) -> Bool {
        // 1. 检查快捷键是否已被占用
        guard !isHotKeyConflict(config) else {
            showConflictAlert(for: action)
            return false
        }
        
        // 2. 注销旧的快捷键
        unregisterHotKey(action)
        
        // 3. 注册新的快捷键
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(action.rawValue.fourCharCode), id: UInt32(action.hashValue))
        
        let status = RegisterEventHotKey(
            config.keyCode,
            config.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        guard status == noErr, let hotKey = hotKeyRef else {
            return false
        }
        
        // 4. 保存注册信息
        registeredHotKeys[action] = hotKey
        hotKeys[action] = config
        
        // 5. 持久化配置
        saveConfiguration()
        
        return true
    }
    
    private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        
        guard status == noErr else { return status }
        
        // 根据 hotKeyID 执行对应操作
        executeHotKeyAction(hotKeyID)
        
        return noErr
    }
}
```

##### 4. 快捷键设置界面
```swift
struct HotKeySettingsView: View {
    @StateObject private var hotKeyManager = HotKeyManager.shared
    @State private var isRecording: HotKeyAction? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("快捷键设置")
                .font(.title2)
                .fontWeight(.semibold)
            
            ForEach(HotKeyAction.allCases, id: \.self) { action in
                HotKeyRow(
                    action: action,
                    config: hotKeyManager.hotKeys[action] ?? action.defaultConfig,
                    isRecording: isRecording == action,
                    onStartRecording: { isRecording = action },
                    onStopRecording: { isRecording = nil },
                    onConfigChanged: { config in
                        hotKeyManager.registerHotKey(action, config: config)
                    }
                )
            }
        }
        .padding()
    }
}

struct HotKeyRow: View {
    let action: HotKeyAction
    let config: HotKeyConfig
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onConfigChanged: (HotKeyConfig) -> Void
    
    var body: some View {
        HStack {
            Text(config.description)
                .frame(width: 120, alignment: .leading)
            
            Button(action: isRecording ? onStopRecording : onStartRecording) {
                Text(isRecording ? "按下快捷键..." : config.displayString)
                    .foregroundColor(isRecording ? .orange : .primary)
                    .frame(minWidth: 100)
            }
            .buttonStyle(.bordered)
            
            Toggle("启用", isOn: .constant(config.isEnabled))
                .toggleStyle(.switch)
        }
        .onKeyDown { event in
            if isRecording {
                let newConfig = HotKeyConfig(
                    keyCode: UInt32(event.keyCode),
                    modifiers: event.modifierFlags.carbonFlags,
                    isEnabled: config.isEnabled,
                    description: config.description
                )
                onConfigChanged(newConfig)
                onStopRecording()
            }
        }
    }
}
```

---

## 🔧 功能2: 截屏时自动隐藏主窗口

### 📝 功能描述
当启动截屏或录屏时，自动将截屏软件窗口隐藏，同时支持在状态栏显示截屏或录屏的图标。

### 🎯 用户需求

- 截屏时主窗口自动隐藏，避免干扰
- 状态栏显示当前操作状态
- 提供快速停止录制的入口
- 支持手动显示/隐藏主窗口

### 🏗 技术实现方案

#### 核心组件
```swift
class WindowManager: ObservableObject {
    @Published var isMainWindowVisible = true
    @Published var captureState: CaptureState = .idle
    
    private var statusBarItem: NSStatusItem?
    private var statusBarMenu: NSMenu?
}

enum CaptureState {
    case idle
    case screenshotting
    case recording(startTime: Date)
    case paused(duration: TimeInterval)
}
```

#### 详细实现逻辑

##### 1. 窗口管理器
```swift
class WindowManager: ObservableObject {
    static let shared = WindowManager()
    
    @Published var isMainWindowVisible = true
    @Published var captureState: CaptureState = .idle
    
    private var statusBarItem: NSStatusItem?
    private var mainWindow: NSWindow?
    
    private init() {
        setupStatusBar()
        observeCaptureState()
    }
    
    // 设置状态栏
    private func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem?.button {
            button.image = NSImage(systemSymbolName: "camera", accessibilityDescription: "MacScreenCapture")
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }
        
        setupStatusBarMenu()
    }
    
    // 状态栏菜单
    private func setupStatusBarMenu() {
        statusBarMenu = NSMenu()
        
        let showWindowItem = NSMenuItem(title: "显示主窗口", action: #selector(showMainWindow), keyEquivalent: "")
        let hideWindowItem = NSMenuItem(title: "隐藏主窗口", action: #selector(hideMainWindow), keyEquivalent: "")
        let separatorItem = NSMenuItem.separator()
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApplication), keyEquivalent: "q")
        
        statusBarMenu?.addItem(showWindowItem)
        statusBarMenu?.addItem(hideWindowItem)
        statusBarMenu?.addItem(separatorItem)
        statusBarMenu?.addItem(quitItem)
        
        statusBarItem?.menu = statusBarMenu
    }
    
    // 监听截图状态变化
    private func observeCaptureState() {
        $captureState
            .sink { [weak self] state in
                self?.updateStatusBarForState(state)
                self?.handleWindowVisibilityForState(state)
            }
            .store(in: &cancellables)
    }
    
    // 根据状态更新状态栏
    private func updateStatusBarForState(_ state: CaptureState) {
        DispatchQueue.main.async { [weak self] in
            guard let button = self?.statusBarItem?.button else { return }
            
            switch state {
            case .idle:
                button.image = NSImage(systemSymbolName: "camera", accessibilityDescription: "MacScreenCapture")
                button.toolTip = "MacScreenCapture - 空闲"
                
            case .screenshotting:
                button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "截图中")
                button.toolTip = "正在截图..."
                
            case .recording(let startTime):
                button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "录制中")
                let duration = Date().timeIntervalSince(startTime)
                button.toolTip = "录制中 - \(formatDuration(duration))"
                
            case .paused(let duration):
                button.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "已暂停")
                button.toolTip = "录制已暂停 - \(formatDuration(duration))"
            }
        }
    }
    
    // 根据状态处理窗口显示/隐藏
    private func handleWindowVisibilityForState(_ state: CaptureState) {
        switch state {
        case .screenshotting, .recording:
            if isMainWindowVisible {
                hideMainWindow()
            }
        case .idle:
            // 截图完成后可以选择是否自动显示窗口
            if UserDefaults.standard.bool(forKey: "autoShowWindowAfterCapture") {
                showMainWindow()
            }
        case .paused:
            break // 暂停时保持当前状态
        }
    }
    
    @objc private func showMainWindow() {
        isMainWindowVisible = true
        NSApp.setActivationPolicy(.regular)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func hideMainWindow() {
        isMainWindowVisible = false
        mainWindow?.orderOut(nil)
        // 保持应用在后台运行，但不显示在 Dock 中
        NSApp.setActivationPolicy(.accessory)
    }
}
```

##### 2. 与截图模块集成
```swift
extension CaptureManager {
    func startScreenshot(type: ScreenshotType) async {
        // 1. 更新状态
        WindowManager.shared.captureState = .screenshotting
        
        // 2. 等待窗口隐藏动画完成
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3秒
        
        // 3. 执行截图
        let result = await performScreenshot(type: type)
        
        // 4. 恢复状态
        WindowManager.shared.captureState = .idle
        
        // 5. 处理截图结果
        handleScreenshotResult(result)
    }
    
    func startRecording() async {
        WindowManager.shared.captureState = .recording(startTime: Date())
        
        // 执行录制逻辑...
    }
    
    func stopRecording() async {
        WindowManager.shared.captureState = .idle
        
        // 停止录制逻辑...
    }
}
```

---

## 🔧 功能3: 截屏后置顶浮窗

### 📝 功能描述
当截屏后，将图片以浮窗的形式展示，且支持在浮窗内进行修改图片、复制、保存等操作。

### 🎯 用户需求
- 截图后立即显示预览浮窗
- 浮窗始终置顶显示
- 支持基础编辑功能（裁剪、标注、马赛克）
- 快速操作（复制、保存、分享）
- 可拖拽移动和调整大小

### 🏗 技术实现方案

#### 核心组件架构
```
ScreenshotFloatingWindow
├── FloatingWindowController (窗口控制)
├── ImagePreviewView (图片预览)
├── EditingToolbar (编辑工具栏)
├── QuickActionBar (快速操作栏)
└── ImageEditor (图片编辑引擎)
```

#### 详细实现逻辑

##### 1. 浮窗控制器
```swift
class FloatingWindowController: NSWindowController {
    private var screenshot: NSImage
    private var editingSession: ImageEditingSession
    
    init(screenshot: NSImage) {
        self.screenshot = screenshot
        self.editingSession = ImageEditingSession(originalImage: screenshot)
        
        // 创建浮窗
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        setupWindow()
        setupContent()
    }
    
    private func setupWindow() {
        guard let window = window else { return }
        
        // 窗口属性设置
        window.title = "截图预览"
        window.level = .floating  // 置顶显示
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        // 居中显示
        window.center()
        
        // 设置最小尺寸
        window.minSize = NSSize(width: 400, height: 300)
        
        // 窗口动画
        window.animationBehavior = .documentWindow
    }
    
    private func setupContent() {
        let contentView = FloatingWindowContentView(
            screenshot: screenshot,
            editingSession: editingSession,
            onSave: { [weak self] editedImage in
                self?.saveImage(editedImage)
            },
            onCopy: { [weak self] editedImage in
                self?.copyToClipboard(editedImage)
            },
            onClose: { [weak self] in
                self?.close()
            }
        )
        
        window?.contentView = NSHostingView(rootView: contentView)
    }
}
```

##### 2. 浮窗内容视图
```swift
struct FloatingWindowContentView: View {
    let screenshot: NSImage
    @ObservedObject var editingSession: ImageEditingSession
    
    let onSave: (NSImage) -> Void
    let onCopy: (NSImage) -> Void
    let onClose: () -> Void
    
    @State private var selectedTool: EditingTool = .none
    @State private var isEditing = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            EditingToolbar(
                selectedTool: $selectedTool,
                onToolSelected: { tool in
                    selectedTool = tool
                    isEditing = tool != .none
                }
            )
            .padding(.horizontal)
            .padding(.top, 8)
            
            // 图片预览和编辑区域
            GeometryReader { geometry in
                ImageEditingCanvas(
                    image: screenshot,
                    editingSession: editingSession,
                    selectedTool: selectedTool,
                    canvasSize: geometry.size
                )
            }
            .background(Color.black.opacity(0.1))
            
            // 快速操作栏
            QuickActionBar(
                onSave: { onSave(editingSession.currentImage) },
                onCopy: { onCopy(editingSession.currentImage) },
                onUndo: { editingSession.undo() },
                onRedo: { editingSession.redo() },
                onClose: onClose,
                canUndo: editingSession.canUndo,
                canRedo: editingSession.canRedo
            )
            .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
```

##### 3. 图片编辑画布
```swift
struct ImageEditingCanvas: View {
    let image: NSImage
    @ObservedObject var editingSession: ImageEditingSession
    let selectedTool: EditingTool
    let canvasSize: CGSize
    
    @State private var currentStroke: EditingStroke?
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            // 背景图片
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipped()
            
            // 编辑层
            Canvas { context, size in
                // 绘制所有编辑操作
                for operation in editingSession.operations {
                    drawOperation(operation, in: context, size: size)
                }
                
                // 绘制当前正在进行的操作
                if let currentStroke = currentStroke {
                    drawStroke(currentStroke, in: context, size: size)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDragChanged(value)
                    }
                    .onEnded { value in
                        handleDragEnded(value)
                    }
            )
        }
        .onTapGesture(count: 2) {
            // 双击退出编辑模式
            selectedTool = .none
        }
    }
    
    private func handleDragChanged(_ value: DragGesture.Value) {
        switch selectedTool {
        case .pen, .highlighter:
            updateCurrentStroke(with: value.location)
        case .rectangle, .circle:
            updateCurrentShape(with: value.startLocation, end: value.location)
        case .arrow:
            updateCurrentArrow(from: value.startLocation, to: value.location)
        case .text:
            // 文本工具在点击时处理
            break
        case .mosaic:
            applyMosaicEffect(at: value.location)
        case .none:
            break
        }
    }
    
    private func handleDragEnded(_ value: DragGesture.Value) {
        guard let stroke = currentStroke else { return }
        
        // 将当前操作添加到编辑会话
        editingSession.addOperation(EditingOperation(
            type: selectedTool,
            stroke: stroke,
            timestamp: Date()
        ))
        
        currentStroke = nil
    }
}
```

##### 4. 图片编辑会话管理
```swift
class ImageEditingSession: ObservableObject {
    @Published var operations: [EditingOperation] = []
    @Published var currentImage: NSImage
    
    private let originalImage: NSImage
    private var undoStack: [EditingOperation] = []
    private var redoStack: [EditingOperation] = []
    
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    
    init(originalImage: NSImage) {
        self.originalImage = originalImage
        self.currentImage = originalImage
    }
    
    func addOperation(_ operation: EditingOperation) {
        operations.append(operation)
        undoStack.append(operation)
        redoStack.removeAll()
        
        updateCurrentImage()
    }
    
    func undo() {
        guard let lastOperation = undoStack.popLast() else { return }
        
        redoStack.append(lastOperation)
        operations.removeAll { $0.id == lastOperation.id }
        
        updateCurrentImage()
    }
    
    func redo() {
        guard let operation = redoStack.popLast() else { return }
        
        operations.append(operation)
        undoStack.append(operation)
        
        updateCurrentImage()
    }
    
    private func updateCurrentImage() {
        // 基于原始图片和所有操作重新生成当前图片
        currentImage = renderImageWithOperations(originalImage, operations: operations)
    }
    
    private func renderImageWithOperations(_ baseImage: NSImage, operations: [EditingOperation]) -> NSImage {
        let size = baseImage.size
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        // 绘制原始图片
        baseImage.draw(in: NSRect(origin: .zero, size: size))
        
        // 应用所有编辑操作
        for operation in operations {
            applyOperation(operation, in: NSRect(origin: .zero, size: size))
        }
        
        image.unlockFocus()
        
        return image
    }
}
```

## 🔧 功能4: 滚动截屏

### 📝 功能描述
当截取应用程序时，支持自动对窗口内进行滚动，然后截取长图。

### 🎯 用户需求
- 自动检测可滚动区域
- 智能滚动并拼接截图
- 支持网页、文档等长内容截取
- 提供滚动进度提示
- 处理动态内容和延迟加载

### 🏗 技术实现方案

#### 核心技术挑战
1. **滚动区域检测**: 识别窗口中的可滚动元素
2. **自动滚动控制**: 模拟用户滚动操作
3. **图片拼接算法**: 处理重叠区域和对齐
4. **内容变化检测**: 处理动态加载内容

#### 详细实现逻辑

##### 1. 滚动截图管理器
```swift
class ScrollScreenshotManager: ObservableObject {
    @Published var isCapturing = false
    @Published var progress: Double = 0
    @Published var status: ScrollCaptureStatus = .idle
    
    private let accessibilityManager = AccessibilityManager()
    private let imageStitcher = ImageStitcher()
    
    func captureScrollingWindow(_ windowInfo: WindowInfo) async throws -> NSImage {
        status = .analyzing
        
        // 1. 分析窗口结构
        let scrollableElements = try await analyzeWindowStructure(windowInfo)
        
        guard let mainScrollElement = selectBestScrollElement(scrollableElements) else {
            throw ScrollCaptureError.noScrollableContent
        }
        
        // 2. 准备截图
        status = .preparing
        let initialScreenshot = try await captureInitialScreenshot(windowInfo)
        let scrollInfo = try await analyzeScrollableArea(mainScrollElement)
        
        // 3. 执行滚动截图
        status = .capturing
        let screenshots = try await performScrollCapture(
            windowInfo: windowInfo,
            scrollElement: mainScrollElement,
            scrollInfo: scrollInfo
        )
        
        // 4. 拼接图片
        status = .stitching
        let finalImage = try await imageStitcher.stitchImages(screenshots)
        
        status = .completed
        return finalImage
    }
    
    private func analyzeWindowStructure(_ windowInfo: WindowInfo) async throws -> [ScrollableElement] {
        // 使用 Accessibility API 分析窗口结构
        let axWindow = try accessibilityManager.getAXWindow(for: windowInfo.windowID)
        
        var scrollableElements: [ScrollableElement] = []
        
        // 递归查找可滚动元素
        func findScrollableElements(_ element: AXUIElement) {
            // 检查元素是否可滚动
            if let scrollBars = try? element.scrollBars(), !scrollBars.isEmpty {
                let scrollableElement = ScrollableElement(
                    axElement: element,
                    bounds: try? element.frame() ?? .zero,
                    scrollBars: scrollBars
                )
                scrollableElements.append(scrollableElement)
            }
            
            // 递归检查子元素
            if let children = try? element.children() {
                for child in children {
                    findScrollableElements(child)
                }
            }
        }
        
        findScrollableElements(axWindow)
        return scrollableElements
    }
    
    private func performScrollCapture(
        windowInfo: WindowInfo,
        scrollElement: ScrollableElement,
        scrollInfo: ScrollInfo
    ) async throws -> [ScreenshotSegment] {
        
        var screenshots: [ScreenshotSegment] = []
        var currentScrollPosition: CGFloat = 0
        let scrollStep: CGFloat = scrollInfo.visibleHeight * 0.8 // 20% 重叠
        
        // 重置滚动位置到顶部
        try await scrollToPosition(scrollElement, position: 0)
        await Task.sleep(nanoseconds: 500_000_000) // 等待滚动完成
        
        while currentScrollPosition < scrollInfo.totalHeight {
            // 截取当前可见区域
            let screenshot = try await captureVisibleArea(windowInfo, scrollElement)
            
            let segment = ScreenshotSegment(
                image: screenshot,
                scrollPosition: currentScrollPosition,
                visibleRect: scrollElement.bounds
            )
            screenshots.append(segment)
            
            // 更新进度
            progress = Double(currentScrollPosition) / Double(scrollInfo.totalHeight)
            
            // 滚动到下一个位置
            currentScrollPosition += scrollStep
            
            if currentScrollPosition < scrollInfo.totalHeight {
                try await scrollToPosition(scrollElement, position: currentScrollPosition)
                
                // 等待内容加载和滚动动画完成
                await waitForContentStabilization(scrollElement)
            }
        }
        
        return screenshots
    }
    
    private func scrollToPosition(_ element: ScrollableElement, position: CGFloat) async throws {
        // 使用 Accessibility API 控制滚动
        if let verticalScrollBar = element.scrollBars.first(where: { $0.orientation == .vertical }) {
            let normalizedPosition = position / element.scrollInfo.totalHeight
            try verticalScrollBar.setValue(normalizedPosition)
        } else {
            // 备用方案：使用鼠标滚轮事件
            try await simulateScrollWheel(in: element.bounds, delta: position)
        }
    }
    
    private func waitForContentStabilization(_ element: ScrollableElement) async {
        // 等待动态内容加载完成
        let maxWaitTime: TimeInterval = 2.0
        let checkInterval: TimeInterval = 0.1
        var elapsedTime: TimeInterval = 0
        
        var previousHash: Int = 0
        
        while elapsedTime < maxWaitTime {
            await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
            
            // 检查内容是否稳定（简化版本：比较截图哈希）
            let currentScreenshot = try? await captureVisibleArea(windowInfo, element)
            let currentHash = currentScreenshot?.hash ?? 0
            
            if currentHash == previousHash && previousHash != 0 {
                // 内容稳定，可以继续
                break
            }
            
            previousHash = currentHash
            elapsedTime += checkInterval
        }
        
        // 额外等待时间确保内容完全加载
        await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
    }
}
```

##### 2. 图片拼接算法
```swift
class ImageStitcher {
    func stitchImages(_ segments: [ScreenshotSegment]) async throws -> NSImage {
        guard !segments.isEmpty else {
            throw StitchingError.noSegments
        }
        
        if segments.count == 1 {
            return segments[0].image
        }
        
        // 计算最终图片尺寸
        let finalSize = calculateFinalSize(segments)
        
        // 创建最终图片
        let finalImage = NSImage(size: finalSize)
        finalImage.lockFocus()
        
        // 设置背景色
        NSColor.white.setFill()
        NSRect(origin: .zero, size: finalSize).fill()
        
        var currentY: CGFloat = 0
        
        for (index, segment) in segments.enumerated() {
            if index == 0 {
                // 第一张图片直接绘制
                segment.image.draw(
                    in: NSRect(x: 0, y: currentY, width: finalSize.width, height: segment.image.size.height),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1.0
                )
                currentY += segment.image.size.height
            } else {
                // 后续图片需要处理重叠区域
                let previousSegment = segments[index - 1]
                let overlapHeight = calculateOverlap(previousSegment, segment)
                
                // 只绘制非重叠部分
                let sourceRect = NSRect(
                    x: 0,
                    y: overlapHeight,
                    width: segment.image.size.width,
                    height: segment.image.size.height - overlapHeight
                )
                
                let destRect = NSRect(
                    x: 0,
                    y: currentY - overlapHeight,
                    width: finalSize.width,
                    height: segment.image.size.height - overlapHeight
                )
                
                segment.image.draw(
                    in: destRect,
                    from: sourceRect,
                    operation: .sourceOver,
                    fraction: 1.0
                )
                
                currentY += (segment.image.size.height - overlapHeight)
            }
        }
        
        finalImage.unlockFocus()
        return finalImage
    }
    
    private func calculateOverlap(_ segment1: ScreenshotSegment, _ segment2: ScreenshotSegment) -> CGFloat {
        // 使用图像匹配算法找到最佳重叠区域
        let searchHeight: CGFloat = min(segment1.image.size.height * 0.3, 100) // 搜索区域高度
        
        let bottomPart = extractImagePart(
            segment1.image,
            rect: NSRect(
                x: 0,
                y: segment1.image.size.height - searchHeight,
                width: segment1.image.size.width,
                height: searchHeight
            )
        )
        
        let topPart = extractImagePart(
            segment2.image,
            rect: NSRect(
                x: 0,
                y: 0,
                width: segment2.image.size.width,
                height: searchHeight
            )
        )
        
        // 使用模板匹配找到最佳重叠位置
        let bestMatch = findBestMatch(template: bottomPart, in: topPart)
        
        return bestMatch.overlapHeight
    }
    
    private func findBestMatch(template: NSImage, in searchImage: NSImage) -> MatchResult {
        // 简化的模板匹配算法
        // 在实际实现中，可以使用更复杂的图像匹配算法
        
        let templateHeight = template.size.height
        let searchHeight = searchImage.size.height
        
        var bestScore: Double = 0
        var bestOverlap: CGFloat = 0
        
        // 在搜索范围内寻找最佳匹配
        for overlap in stride(from: CGFloat(10), through: min(templateHeight, searchHeight) - 10, by: 5) {
            let score = calculateSimilarity(
                template: template,
                searchImage: searchImage,
                overlap: overlap
            )
            
            if score > bestScore {
                bestScore = score
                bestOverlap = overlap
            }
        }
        
        return MatchResult(overlapHeight: bestOverlap, confidence: bestScore)
    }
}
```

##### 3. 用户界面集成
```swift
struct ScrollScreenshotView: View {
    @StateObject private var scrollManager = ScrollScreenshotManager()
    @State private var selectedWindow: WindowInfo?
    @State private var showingResult = false
    @State private var resultImage: NSImage?
    
    var body: some View {
        VStack(spacing: 20) {
            // 窗口选择
            WindowSelectionView(selectedWindow: $selectedWindow)
            
            // 开始按钮
            Button("开始滚动截图") {
                startScrollCapture()
            }
            .disabled(selectedWindow == nil || scrollManager.isCapturing)
            
            // 进度显示
            if scrollManager.isCapturing {
                VStack(spacing: 10) {
                    Text(scrollManager.status.description)
                        .font(.headline)
                    
                    ProgressView(value: scrollManager.progress)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    Text("\(Int(scrollManager.progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .sheet(isPresented: $showingResult) {
            if let image = resultImage {
                ScrollScreenshotResultView(image: image)
            }
        }
    }
    
    private func startScrollCapture() {
        guard let window = selectedWindow else { return }
        
        Task {
            do {
                let result = try await scrollManager.captureScrollingWindow(window)
                
                await MainActor.run {
                    resultImage = result
                    showingResult = true
                }
            } catch {
                // 处理错误
                print("滚动截图失败: \(error)")
            }
        }
    }
}
```

---

## 📊 开发计划与里程碑

### 第一周：基础功能开发
- **Day 1-2**: 快捷键系统开发
- **Day 3-4**: 窗口管理和状态栏功能
- **Day 5**: 集成测试和 Bug 修复

### 第二周：高级功能开发
- **Day 1-3**: 截屏后置顶浮窗开发
- **Day 4-5**: 基础图片编辑功能

### 第三周：滚动截屏开发
- **Day 1-2**: 滚动检测和控制逻辑
- **Day 3-4**: 图片拼接算法
- **Day 5**: 用户界面和体验优化

### 第四周：测试和优化
- **Day 1-2**: 功能测试和性能优化
- **Day 3-4**: 用户体验改进
- **Day 5**: 发布准备

---

## 🧪 测试策略

### 单元测试
- 快捷键注册和冲突检测
- 图片拼接算法准确性
- 编辑操作的撤销/重做功能

### 集成测试
- 不同应用程序的滚动截图兼容性
- 多显示器环境下的窗口管理
- 系统权限和安全性测试

### 用户体验测试
- 快捷键响应速度
- 浮窗操作流畅性
- 滚动截图的准确性和完整性

---

## 🔒 安全和权限考虑

### 系统权限
- **辅助功能权限**: 滚动截图需要控制其他应用
- **屏幕录制权限**: 截图功能的基础权限
- **输入监控权限**: 全局快捷键监听

### 隐私保护
- 敏感内容检测和提醒
- 截图数据的本地存储加密
- 用户数据不上传云端

### 安全措施
- 代码签名和公证
- 沙盒环境运行
- 最小权限原则

---

## 📈 性能优化

### 内存管理
- 大图片的分块处理
- 及时释放不需要的图片资源
- 使用图片缓存策略

### 响应性优化
- 异步处理耗时操作
- 进度反馈和用户提示
- 后台任务管理

### 资源使用
- CPU 使用率控制
- 磁盘空间管理
- 网络请求优化（如果有）

---

## 🎯 成功指标

### 功能指标
- 快捷键响应时间 < 100ms
- 滚动截图成功率 > 95%
- 图片拼接准确率 > 98%

### 用户体验指标
- 应用启动时间 < 2s
- 截图操作完成时间 < 3s
- 用户操作流畅度评分 > 4.5/5

### 稳定性指标
- 崩溃率 < 0.1%
- 内存泄漏检测通过
- 长时间运行稳定性测试通过