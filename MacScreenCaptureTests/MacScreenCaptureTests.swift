//
//  MacScreenCaptureTests.swift
//  MacScreenCaptureTests
//
//  Created by Developer on 2025/9/25.
//

import XCTest
import AppKit
import Carbon
@testable import MacScreenCapture

final class MacScreenCaptureTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testPermissionManagerInitialization() throws {
        let permissionManager = PermissionManager()
        XCTAssertNotNil(permissionManager)
        XCTAssertFalse(permissionManager.permissionCheckInProgress)
    }
    
    @MainActor
    func testCaptureManagerInitialization() throws {
        let captureManager = CaptureManager()
        XCTAssertNotNil(captureManager)
        XCTAssertFalse(captureManager.isRecording)
        XCTAssertFalse(captureManager.isPaused)
        XCTAssertEqual(captureManager.recordingDuration, 0)
        XCTAssertEqual(captureManager.captureMode, .fullScreen)
    }
    
    func testCaptureModeEnum() throws {
        let allCases = CaptureMode.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.fullScreen))
        XCTAssertTrue(allCases.contains(.window))
        XCTAssertTrue(allCases.contains(.region))
        
        XCTAssertEqual(CaptureMode.fullScreen.rawValue, "全屏")
        XCTAssertEqual(CaptureMode.window.rawValue, "窗口")
        XCTAssertEqual(CaptureMode.region.rawValue, "区域")
        
        XCTAssertEqual(CaptureMode.fullScreen.systemImage, "display")
        XCTAssertEqual(CaptureMode.window.systemImage, "macwindow")
        XCTAssertEqual(CaptureMode.region.systemImage, "crop")
    }

    func testIShotStyleDefaultHotKeysAreAvailableAtLaunch() throws {
        let expectedHotKeys: [HotKeyAction: (keyCode: UInt32, modifiers: UInt32, display: String)] = [
            .fullScreenshot: (UInt32(kVK_ANSI_S), UInt32(cmdKey | shiftKey), "⌘⇧S"),
            .regionScreenshot: (UInt32(kVK_ANSI_A), UInt32(cmdKey | shiftKey), "⌘⇧A"),
            .windowScreenshot: (UInt32(kVK_ANSI_W), UInt32(cmdKey | shiftKey), "⌘⇧W"),
            .delayedScreenshot: (UInt32(kVK_ANSI_L), UInt32(cmdKey | optionKey), "⌘⌥L"),
            .multiWindowScreenshot: (UInt32(kVK_ANSI_W), UInt32(cmdKey | optionKey), "⌘⌥W"),
            .deviceFramedScreenshot: (UInt32(kVK_ANSI_F), UInt32(cmdKey | optionKey), "⌘⌥F"),
            .startRecording: (UInt32(kVK_ANSI_W), UInt32(optionKey), "⌥W"),
            .startAudioRecording: (UInt32(kVK_ANSI_M), UInt32(cmdKey | shiftKey), "⌘⇧M"),
            .togglePauseRecording: (UInt32(kVK_Space), UInt32(cmdKey | optionKey), "⌘⌥Space"),
            .stopRecording: (UInt32(kVK_ANSI_R), UInt32(cmdKey | shiftKey), "⌘⇧R"),
            .scrollScreenshot: (UInt32(kVK_ANSI_S), UInt32(cmdKey | optionKey), "⌘⌥S"),
            .pickColor: (UInt32(kVK_ANSI_C), UInt32(cmdKey | shiftKey), "⌘⇧C"),
            .pinnedScreenshot: (UInt32(kVK_ANSI_P), UInt32(cmdKey | optionKey), "⌘⌥P"),
            .ocrScreenshot: (UInt32(kVK_ANSI_O), UInt32(cmdKey | optionKey), "⌘⌥O"),
            .translateScreenshot: (UInt32(kVK_ANSI_T), UInt32(cmdKey | optionKey), "⌘⌥T")
        ]

        XCTAssertEqual(Set(expectedHotKeys.keys), Set(HotKeyAction.allCases))

        for (action, expected) in expectedHotKeys {
            let config = action.defaultConfig
            XCTAssertEqual(config.keyCode, expected.keyCode, action.localizedDescription)
            XCTAssertEqual(config.modifiers, expected.modifiers, action.localizedDescription)
            XCTAssertEqual(config.displayString, expected.display, action.localizedDescription)
            XCTAssertTrue(config.isEnabled, action.localizedDescription)
        }
    }

    func testReleaseWorkflowBuildsUniversalMacArtifacts() throws {
        let workflow = try repositoryFileContents(".github/workflows/build-and-release.yml")

        XCTAssertTrue(workflow.contains("ARCHS=\"arm64 x86_64\""))
        XCTAssertTrue(workflow.contains("ONLY_ACTIVE_ARCH=NO"))
        XCTAssertTrue(workflow.contains("lipo -archs"))
        XCTAssertTrue(workflow.contains("arm64"))
        XCTAssertTrue(workflow.contains("x86_64"))
    }

    func testMainScreenshotViewExposesIShotAdvancedActions() throws {
        let source = try repositoryFileContents("MacScreenCapture/Views/ScreenshotView.swift")
        let expectedActions = [
            ("延时", "captureDelayedScreenshot()"),
            ("长截图", "captureScrollingWindow()"),
            ("多窗口", "captureMultipleWindowsScreenshot()"),
            ("带壳", "captureDeviceFramedFullScreen()"),
            ("贴图", "capturePinnedRegion()"),
            ("取色", "pickScreenColor()"),
            ("OCR", "captureRegionAndRecognizeText()"),
            ("翻译", "captureRegionAndTranslate()")
        ]

        for (title, methodCall) in expectedActions {
            XCTAssertTrue(source.contains("AdvancedActionButton(title: \"\(title)\""), title)
            XCTAssertTrue(source.contains(methodCall), title)
        }
    }

    func testMenuBarExposesIShotAndProActions() throws {
        let source = try repositoryFileContents("MacScreenCapture/Views/MenuBarView.swift")
        let expectedEntries = [
            ("全屏截图", "⌘⇧S", "quickScreenshot(.fullScreen)"),
            ("窗口截图", "⌘⇧W", "quickScreenshot(.window)"),
            ("区域截图", "⌘⇧A", "quickScreenshot(.region)"),
            ("延时截图", "⌘⌥L", "quickDelayedScreenshot()"),
            ("长截图", "⌘⌥S", "quickScrollingScreenshot()"),
            ("多窗口截图", "⌘⌥W", "quickMultiWindowScreenshot()"),
            ("全屏带壳截图", "⌘⌥F", "quickDeviceFramedScreenshot()"),
            ("取色", "⌘⇧C", "pickScreenColor()"),
            ("OCR 识别", "⌘⌥O", "quickOCR()"),
            ("截图翻译", "⌘⌥T", "quickTranslate()"),
            ("贴图", "⌘⌥P", "quickPinnedScreenshot()"),
            ("开始录制", "⌥W", "quickRecording()"),
            ("开始录音", "⌘⇧M", "quickAudioRecording()")
        ]

        for (title, shortcut, methodCall) in expectedEntries {
            XCTAssertTrue(source.contains("title: \"\(title)\""), title)
            XCTAssertTrue(source.contains("shortcut: \"\(shortcut)\""), title)
            XCTAssertTrue(source.contains(methodCall), title)
        }

        XCTAssertTrue(source.contains("用指定 App 打开"))
        XCTAssertTrue(source.contains("quickOpenInConfiguredApp()"))
        XCTAssertTrue(source.contains("⌘⌥Space"))
        XCTAssertTrue(source.contains("togglePauseRecording()"))
        XCTAssertTrue(source.contains("⌘⇧R"))
        XCTAssertTrue(source.contains("stopRecording()"))
    }

    func testEditingToolsCoverIShotAnnotationSuite() throws {
        let expectedTools: [(EditingTool, String, String)] = [
            (.none, "选择", "hand.point.up.left"),
            (.pen, "画笔", "pencil"),
            (.highlighter, "荧光笔", "highlighter"),
            (.rectangle, "矩形", "rectangle"),
            (.circle, "圆形", "circle"),
            (.arrow, "箭头", "arrow.up.right"),
            (.text, "文字", "textformat"),
            (.numbered, "序号", "1.circle"),
            (.mosaic, "马赛克", "mosaic"),
            (.crop, "裁剪", "crop")
        ]

        XCTAssertEqual(EditingTool.allCases, expectedTools.map(\.0))

        for (tool, name, icon) in expectedTools {
            XCTAssertEqual(tool.name, name)
            XCTAssertEqual(tool.icon, icon)
        }
    }

    func testAnnotationSettingsExposeNumberStyleAndTemplateControls() throws {
        let settingsSource = try repositoryFileContents("MacScreenCapture/Views/SettingsView.swift")
        let editorSource = try repositoryFileContents("MacScreenCapture/Views/FloatingWindowContentView.swift")
        let editingWindowSource = try repositoryFileContents("MacScreenCapture/Views/EditingWindowContentView.swift")

        XCTAssertTrue(settingsSource.contains("Stepper(\"数字序号起始值:"))
        XCTAssertTrue(settingsSource.contains("Text(\"默认颜色:\")"))
        XCTAssertTrue(settingsSource.contains("Text(\"默认字号:\")"))
        XCTAssertTrue(settingsSource.contains("Toggle(\"文字和序号启用描边\""))
        XCTAssertTrue(settingsSource.contains("Button(\"导出模板\")"))
        XCTAssertTrue(settingsSource.contains("Button(\"导入模板\")"))
        XCTAssertTrue(settingsSource.contains("saveCustomAnnotationPreset(.custom)"))
        XCTAssertTrue(settingsSource.contains("saveCustomAnnotationPreset(.custom2)"))
        XCTAssertTrue(settingsSource.contains("saveCustomAnnotationPreset(.custom3)"))

        XCTAssertTrue(editorSource.contains("ForEach(EditingTool.allCases"))
        XCTAssertTrue(editorSource.contains("ColorPicker(\"选择颜色\""))
        XCTAssertTrue(editorSource.contains("Text(\"字号\")"))
        XCTAssertTrue(editorSource.contains("Toggle(\"描边\""))
        XCTAssertTrue(editorSource.contains("disabled(selectedTool != .text && selectedTool != .numbered)"))
        XCTAssertTrue(editorSource.contains("defaultNumberStart()"))
        XCTAssertTrue(editorSource.contains("UserDefaults.standard.integer(forKey: \"numberedAnnotationStart\")"))
        XCTAssertTrue(editorSource.contains("editTextOperation(operation)"))
        XCTAssertTrue(editorSource.contains("moved(by: offset)"))

        XCTAssertTrue(editingWindowSource.contains("EditingToolbar("))
        XCTAssertTrue(editingWindowSource.contains("showingColorPicker: $showingColorPicker"))
    }

    func testRecordingPreflightExposesIShotAudioAndExportControls() throws {
        let captureManagerSource = try repositoryFileContents("MacScreenCapture/Core/CaptureManager.swift")
        let recordingViewSource = try repositoryFileContents("MacScreenCapture/Views/RecordingView.swift")
        let settingsSource = try repositoryFileContents("MacScreenCapture/Views/SettingsView.swift")

        XCTAssertTrue(captureManagerSource.contains("RecordingPreflightSettingsView(audioOnly: audioOnly)"))
        XCTAssertTrue(captureManagerSource.contains("NSButton(checkboxWithTitle: \"录制系统音频\""))
        XCTAssertTrue(captureManagerSource.contains("NSButton(checkboxWithTitle: \"录制麦克风\""))
        XCTAssertTrue(captureManagerSource.contains("NSButton(checkboxWithTitle: \"显示鼠标指针\""))
        XCTAssertTrue(captureManagerSource.contains("frameRatePopup.addItems(withTitles: [\"15 FPS\", \"30 FPS\", \"60 FPS\"])"))
        XCTAssertTrue(captureManagerSource.contains("qualityPopup.addItems(withTitles: [\"低\", \"中\", \"高\", \"超高\"])"))
        XCTAssertTrue(captureManagerSource.contains("formatPopup.addItems(withTitles: [\"MOV\", \"MP4\"])"))
        XCTAssertTrue(captureManagerSource.contains("delayStepper.maxValue = 30"))
        XCTAssertTrue(captureManagerSource.contains("UserDefaults.standard.set(systemAudioCheckbox.state == .on, forKey: \"includeSystemAudio\")"))
        XCTAssertTrue(captureManagerSource.contains("UserDefaults.standard.set(microphoneCheckbox.state == .on, forKey: \"includeMicrophone\")"))
        XCTAssertTrue(captureManagerSource.contains("UserDefaults.standard.set(formatPopup.titleOfSelectedItem ?? \"MOV\", forKey: \"recordingFileFormat\")"))
        XCTAssertTrue(captureManagerSource.contains("waitForRecordingStartDelayIfNeeded(subtitle:"))
        XCTAssertTrue(captureManagerSource.contains("ScreenshotCountdownOverlayController(subtitle: subtitle)"))

        XCTAssertTrue(recordingViewSource.contains("Toggle(\"录制系统音频\""))
        XCTAssertTrue(recordingViewSource.contains("Toggle(\"录制麦克风\""))
        XCTAssertTrue(recordingViewSource.contains("Stepper(\"开录延时:"))
        XCTAssertTrue(recordingViewSource.contains("Picker(\"导出格式\""))
        XCTAssertTrue(recordingViewSource.contains("Text(\"MOV\").tag(\"MOV\")"))
        XCTAssertTrue(recordingViewSource.contains("Text(\"MP4\").tag(\"MP4\")"))
        XCTAssertTrue(recordingViewSource.contains("startRecordingWithPreflight()"))
        XCTAssertTrue(recordingViewSource.contains("startAudioRecordingWithPreflight()"))

        XCTAssertTrue(settingsSource.contains("Picker(\"质量\", selection: $recordingQuality)"))
        XCTAssertTrue(settingsSource.contains("Toggle(\"录制系统音频\", isOn: $includeSystemAudio)"))
        XCTAssertTrue(settingsSource.contains("Toggle(\"录制麦克风\", isOn: $includeMicrophone)"))
        XCTAssertTrue(settingsSource.contains("Stepper(\"开录延时:"))
    }

    func testScreenshotPreviewAndQuickOpenEntrypointsStayWired() throws {
        let screenshotViewSource = try repositoryFileContents("MacScreenCapture/Views/ScreenshotView.swift")
        let settingsSource = try repositoryFileContents("MacScreenCapture/Views/SettingsView.swift")
        let hotKeySource = try repositoryFileContents("MacScreenCapture/Core/HotKeyManager.swift")
        let captureManagerSource = try repositoryFileContents("MacScreenCapture/Core/CaptureManager.swift")

        XCTAssertTrue(screenshotViewSource.contains("Button(\"编辑\")"))
        XCTAssertTrue(screenshotViewSource.contains("WindowManager.shared.showEditingWindow(for: image)"))
        XCTAssertTrue(screenshotViewSource.contains("Button(\"识别文字\")"))
        XCTAssertTrue(screenshotViewSource.contains("recognizeTextFromLastScreenshot()"))
        XCTAssertTrue(screenshotViewSource.contains("Button(\"翻译截图\")"))
        XCTAssertTrue(screenshotViewSource.contains("translateLastScreenshot()"))
        XCTAssertTrue(screenshotViewSource.contains("Button(\"复制到剪贴板\")"))
        XCTAssertTrue(screenshotViewSource.contains("NSPasteboard.general.setData"))
        XCTAssertTrue(screenshotViewSource.contains("Button(\"在Finder中显示\")"))
        XCTAssertTrue(screenshotViewSource.contains("NSWorkspace.shared.selectFile"))

        XCTAssertTrue(settingsSource.contains("Text(\"指定 App 打开:\")"))
        XCTAssertTrue(settingsSource.contains("selectOpenAfterCaptureApp()"))
        XCTAssertTrue(settingsSource.contains("Toggle(\"截图保存后自动用指定 App 打开\""))
        XCTAssertTrue(settingsSource.contains("Toggle(\"双击 ⌥ 后截图并打开指定 App\""))
        XCTAssertTrue(settingsSource.contains("Text(\"双击判定:\")"))
        XCTAssertTrue(settingsSource.contains("Text(\"触发冷却:\")"))

        XCTAssertTrue(hotKeySource.contains("handleModifierFlagsEvent"))
        XCTAssertTrue(hotKeySource.contains("performDoubleOptionQuickOpen()"))
        XCTAssertTrue(hotKeySource.contains("captureRegionAndOpenInConfiguredApp()"))
        XCTAssertTrue(captureManagerSource.contains("func captureRegionAndOpenInConfiguredApp()"))
        XCTAssertTrue(captureManagerSource.contains("openLastScreenshotInConfiguredApp()"))
    }

    func testMultiWindowSelectionSupportsShiftAndDesktopBackdrop() throws {
        let source = try repositoryFileContents("MacScreenCapture/Core/CaptureManager.swift")

        XCTAssertTrue(source.contains("captureMultipleWindowsScreenshot()"))
        XCTAssertTrue(source.contains("captureInteractiveWindowScreenshot()"))
        XCTAssertTrue(source.contains("singleClickCompletes: true"))
        XCTAssertTrue(source.contains("desktopBackdropSelected.toggle()"))
        XCTAssertTrue(source.contains("!event.modifierFlags.contains(.shift)"))
        XCTAssertTrue(source.contains("MultiWindowSelectionResult(windows: [candidate.window], usesDesktopBackdrop: desktopBackdropSelected)"))
        XCTAssertTrue(source.contains("selectedIDs.insert(candidate.id)"))
        XCTAssertTrue(source.contains("case 36, 76:"))
        XCTAssertTrue(source.contains("usesDesktopBackdrop: desktopBackdropSelected"))
        XCTAssertTrue(source.contains("drawDesktopBackdropBadge()"))
        XCTAssertTrue(source.contains("按住 Shift 可连续选择多个窗口"))
        XCTAssertTrue(source.contains("点桌面用壁纸作底板"))
        XCTAssertTrue(source.contains("captureDesktopBackdropSegments("))
        XCTAssertTrue(source.contains("captureDisplayImageWithoutSaving("))
        XCTAssertTrue(source.contains("renderMultiWindowComposite("))
    }

    func testScrollingScreenshotControlsAndExecutionStayAlignedWithIShot() throws {
        let captureManagerSource = try repositoryFileContents("MacScreenCapture/Core/CaptureManager.swift")
        let settingsSource = try repositoryFileContents("MacScreenCapture/Views/SettingsView.swift")

        XCTAssertTrue(settingsSource.contains("Text(\"长截图\")"))
        XCTAssertTrue(settingsSource.contains("Stepper(\"最多截取屏数:"))
        XCTAssertTrue(settingsSource.contains("Slider(value: $scrollingCaptureDelay, in: 0.2...2.0"))
        XCTAssertTrue(settingsSource.contains("Stepper(\"每次滚动:"))
        XCTAssertTrue(settingsSource.contains("Picker(\"滚动方向\""))
        XCTAssertTrue(settingsSource.contains("Text(\"向下\").tag(\"down\")"))
        XCTAssertTrue(settingsSource.contains("Text(\"向上\").tag(\"up\")"))
        XCTAssertTrue(settingsSource.contains("Toggle(\"裁剪到鼠标所在窗口\""))
        XCTAssertTrue(settingsSource.contains("Toggle(\"优先识别窗口内滚动内容区\""))
        XCTAssertTrue(settingsSource.contains("Toggle(\"滚动到底自动停止\""))
        XCTAssertTrue(settingsSource.contains("Toggle(\"自动裁剪重叠区域\""))

        XCTAssertTrue(captureManagerSource.contains("func captureScrollingWindow()"))
        XCTAssertTrue(captureManagerSource.contains("ScrollingCaptureSettings.fromDefaults()"))
        XCTAssertTrue(captureManagerSource.contains("scrollingCaptureTrimOverlap"))
        XCTAssertTrue(captureManagerSource.contains("scrollingCaptureCropToWindow"))
        XCTAssertTrue(captureManagerSource.contains("scrollingCaptureStopWhenUnchanged"))
        XCTAssertTrue(captureManagerSource.contains("scrollingCaptureTargetUnderMouse(from: content)"))
        XCTAssertTrue(captureManagerSource.contains("scrollActiveView(lines: scrollLines, direction: scrollDirection)"))
        XCTAssertTrue(captureManagerSource.contains("captureDisplayImageWithoutSaving(display: target?.display)"))
        XCTAssertTrue(captureManagerSource.contains("cropDisplayImage(image, to: target.cropRect"))
        XCTAssertTrue(captureManagerSource.contains("ScrollingImageStitcher.imagesAreVisuallySimilar(previous, sliceImage)"))
        XCTAssertTrue(captureManagerSource.contains("ScrollingImageStitcher.orderedImages(images, direction: scrollDirection)"))
        XCTAssertTrue(captureManagerSource.contains("ScrollingImageStitcher.stitchImagesVertically(orderedImages, trimOverlap: trimOverlap)"))
        XCTAssertTrue(captureManagerSource.contains("finalizeCapturedImage(stitchedImage, showEditor: true)"))
        XCTAssertTrue(captureManagerSource.contains("scrollingCaptureDetectContentArea"))
        XCTAssertTrue(captureManagerSource.contains("kAXScrollAreaRole"))
        XCTAssertTrue(captureManagerSource.contains("AXWebArea"))
    }

    func testOCRAndTranslationEntrypointsStayAlignedWithIShotPro() throws {
        let captureManagerSource = try repositoryFileContents("MacScreenCapture/Core/CaptureManager.swift")
        let screenshotViewSource = try repositoryFileContents("MacScreenCapture/Views/ScreenshotView.swift")
        let settingsSource = try repositoryFileContents("MacScreenCapture/Views/SettingsView.swift")

        XCTAssertTrue(screenshotViewSource.contains("AdvancedActionButton(title: \"OCR\""))
        XCTAssertTrue(screenshotViewSource.contains("captureRegionAndRecognizeText()"))
        XCTAssertTrue(screenshotViewSource.contains("AdvancedActionButton(title: \"翻译\""))
        XCTAssertTrue(screenshotViewSource.contains("captureRegionAndTranslate()"))
        XCTAssertTrue(screenshotViewSource.contains("recognizeTextFromLastScreenshot()"))
        XCTAssertTrue(screenshotViewSource.contains("translateLastScreenshot()"))

        XCTAssertTrue(captureManagerSource.contains("func captureRegionAndRecognizeText()"))
        XCTAssertTrue(captureManagerSource.contains("captureInteractiveScreenshot(arguments: [\"-i\", \"-r\"], forceStyle: false, showEditor: false, autoOpenAfterCapture: false)"))
        XCTAssertTrue(captureManagerSource.contains("NSPasteboard.general.setString(text, forType: .string)"))
        XCTAssertTrue(captureManagerSource.contains("VNRecognizeTextRequest"))
        XCTAssertTrue(captureManagerSource.contains("request.recognitionLevel = .accurate"))
        XCTAssertTrue(captureManagerSource.contains("request.recognitionLanguages = [\"zh-Hans\", \"zh-Hant\", \"en-US\", \"ja-JP\", \"ko-KR\"]"))
        XCTAssertTrue(captureManagerSource.contains("OCRTextOrderer.joinedText(textBoxes)"))

        XCTAssertTrue(captureManagerSource.contains("func captureRegionAndTranslate()"))
        XCTAssertTrue(captureManagerSource.contains("translationTargetLanguage"))
        XCTAssertTrue(captureManagerSource.contains("translateWithAppleInstalledModel"))
        XCTAssertTrue(captureManagerSource.contains("providerName: \"Apple 本地翻译\""))
        XCTAssertTrue(captureManagerSource.contains("translateWithGoogle"))
        XCTAssertTrue(captureManagerSource.contains("providerName: \"Google\""))
        XCTAssertTrue(captureManagerSource.contains("translateWithMyMemory"))
        XCTAssertTrue(captureManagerSource.contains("providerName: \"MyMemory\""))
        XCTAssertTrue(captureManagerSource.contains("openWebTranslation(for: trimmedText, targetLanguage: targetLanguage)"))
        XCTAssertTrue(captureManagerSource.contains("providerName: \"网页翻译\""))
        XCTAssertTrue(captureManagerSource.contains("showTranslationWindow(result)"))
        XCTAssertTrue(captureManagerSource.contains("prepareAppleTranslationModels(targetLanguage: String)"))

        XCTAssertTrue(settingsSource.contains("Picker(\"截图翻译目标\""))
        XCTAssertTrue(settingsSource.contains("Text(\"简体中文\").tag(\"zh-CN\")"))
        XCTAssertTrue(settingsSource.contains("Text(\"English\").tag(\"en\")"))
        XCTAssertTrue(settingsSource.contains("Text(\"日本語\").tag(\"ja\")"))
        XCTAssertTrue(settingsSource.contains("Text(\"한국어\").tag(\"ko\")"))
        XCTAssertTrue(settingsSource.contains("Button(isPreparingTranslationModels ? \"检查中...\" : \"检查并准备\")"))
        XCTAssertTrue(settingsSource.contains("prepareLocalTranslationModels()"))
    }
    
    func testFileManagerExtensions() throws {
        let screenshotDir = FileManager.defaultScreenshotDirectory
        let recordingDir = FileManager.defaultRecordingDirectory
        
        XCTAssertTrue(screenshotDir.lastPathComponent == "Screenshots")
        XCTAssertTrue(recordingDir.lastPathComponent == "Recordings")
        
        // 测试唯一文件名生成
        let uniqueName = FileManager.generateUniqueFileName(
            baseName: "test",
            extension: "png",
            in: screenshotDir
        )
        XCTAssertTrue(uniqueName.hasSuffix(".png"))
        XCTAssertTrue(uniqueName.hasPrefix("test"))
    }

    @MainActor
    func testCaptureManagerTracksSavedEditedScreenshot() throws {
        let captureManager = CaptureManager()
        let image = makeSolidImage(width: 16, height: 12, color: .systemPurple)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("edited-\(UUID().uuidString).png")
        var observedURL: URL?
        let observer = NotificationCenter.default.addObserver(
            forName: .screenshotDidSave,
            object: nil,
            queue: nil
        ) { notification in
            observedURL = notification.object as? URL
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        captureManager.markScreenshotSaved(image, at: url)

        XCTAssertEqual(observedURL, url)
        XCTAssertEqual(captureManager.lastSavedImageURL, url)
        XCTAssertEqual(captureManager.lastCapturedImage?.size, image.size)
    }

    func testRegisteredDefaultsCoverIShotAndProCapabilities() throws {
        let defaults = UserDefaults.macScreenCaptureDefaults

        XCTAssertEqual(defaults["includeSystemAudio"] as? Bool, true)
        XCTAssertEqual(defaults["includeMicrophone"] as? Bool, true)
        XCTAssertEqual(defaults["recordingFrameRate"] as? Double, 60.0)
        XCTAssertEqual(defaults["recordingQuality"] as? String, "高")
        XCTAssertEqual(defaults["recordingFileFormat"] as? String, "MOV")
        XCTAssertEqual(defaults["showCursor"] as? Bool, true)
        XCTAssertEqual(defaults["delayedScreenshotSeconds"] as? Int, 5)
        XCTAssertEqual(defaults["multiWindowDesktopBackdrop"] as? Bool, true)
        XCTAssertEqual(defaults["scrollingCaptureSlices"] as? Int, 30)
        XCTAssertEqual(defaults["scrollingCaptureDirection"] as? String, "down")
        XCTAssertEqual(defaults["scrollingCaptureTrimOverlap"] as? Bool, true)
        XCTAssertEqual(defaults["scrollingCaptureCropToWindow"] as? Bool, true)
        XCTAssertEqual(defaults["scrollingCaptureDetectContentArea"] as? Bool, true)
        XCTAssertEqual(defaults["scrollingCaptureStopWhenUnchanged"] as? Bool, true)
        XCTAssertEqual(defaults["floatingWindowAlwaysOnTop"] as? Bool, true)
        XCTAssertEqual(defaults["doubleOptionQuickOpenEnabled"] as? Bool, true)
        XCTAssertEqual(defaults["doubleOptionQuickOpenInterval"] as? Double, 0.45)
        XCTAssertEqual(defaults["doubleOptionQuickOpenCooldown"] as? Double, 1.0)
        XCTAssertEqual(defaults["deviceFrameBezelWidth"] as? Double, 42.0)
        XCTAssertEqual(defaults["deviceFramePadding"] as? Double, 48.0)
        XCTAssertEqual(defaults["deviceFrameCornerRadius"] as? Double, 26.0)
        XCTAssertEqual(defaults["deviceFrameShadowRadius"] as? Double, 28.0)
        XCTAssertEqual(defaults["deviceFrameBodyColorHex"] as? String, "#141414")
        XCTAssertEqual(defaults["deviceFrameShadowColorHex"] as? String, "#000000")
        XCTAssertEqual(defaults["annotationStylePreset"] as? String, AnnotationStylePreset.professional.rawValue)
        XCTAssertEqual(defaults["colorCodeFormat"] as? String, "#HEX")
        XCTAssertEqual(defaults["customColorCodeTemplate"] as? String, "{hex}")
        XCTAssertEqual(defaults["translationTargetLanguage"] as? String, "zh-CN")
        XCTAssertEqual(defaults["annotationDefaultFontSize"] as? Double, AnnotationStylePreset.professional.fontSize)
        XCTAssertEqual(defaults["annotationCustomFontSize"] as? Double, AnnotationStylePreset.professional.fontSize)
        XCTAssertEqual(defaults["annotationCustom2FontSize"] as? Double, AnnotationStylePreset.professional.fontSize)
        XCTAssertEqual(defaults["annotationCustom3FontSize"] as? Double, AnnotationStylePreset.professional.fontSize)
    }

    func testRegisteringDefaultsDoesNotOverwriteUserChoices() throws {
        let suiteName = "MacScreenCaptureTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        UserDefaults.registerMacScreenCaptureDefaults(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: "includeSystemAudio"))
        XCTAssertEqual(defaults.string(forKey: "recordingFileFormat"), "MOV")

        defaults.set(false, forKey: "includeSystemAudio")
        defaults.set("MP4", forKey: "recordingFileFormat")
        UserDefaults.registerMacScreenCaptureDefaults(in: defaults)

        XCTAssertFalse(defaults.bool(forKey: "includeSystemAudio"))
        XCTAssertEqual(defaults.string(forKey: "recordingFileFormat"), "MP4")
    }

    func testFloatingWindowConfigurationReadsDefaultsAndClampsOpacity() throws {
        let suiteName = "MacScreenCaptureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        UserDefaults.registerMacScreenCaptureDefaults(in: defaults)
        var configuration = FloatingWindowConfiguration.fromDefaults(defaults)

        XCTAssertTrue(configuration.alwaysOnTop)
        XCTAssertEqual(configuration.windowLevel.rawValue, NSWindow.Level.floating.rawValue)
        XCTAssertTrue(configuration.showShadow)
        XCTAssertEqual(configuration.opacity, 0.95)
        XCTAssertFalse(configuration.closeAfterSave)

        defaults.set(false, forKey: "floatingWindowAlwaysOnTop")
        defaults.set(false, forKey: "floatingWindowShowShadow")
        defaults.set(5.0, forKey: "floatingWindowOpacity")
        defaults.set(true, forKey: "floatingWindowCloseAfterSave")

        configuration = FloatingWindowConfiguration.fromDefaults(defaults)
        XCTAssertFalse(configuration.alwaysOnTop)
        XCTAssertEqual(configuration.windowLevel.rawValue, NSWindow.Level.normal.rawValue)
        XCTAssertFalse(configuration.showShadow)
        XCTAssertEqual(configuration.opacity, 1.0)
        XCTAssertTrue(configuration.closeAfterSave)

        XCTAssertEqual(FloatingWindowConfiguration.normalizedOpacity(0), 0.95)
        XCTAssertEqual(FloatingWindowConfiguration.normalizedOpacity(-1), 0.95)
        XCTAssertEqual(FloatingWindowConfiguration.normalizedOpacity(0.1), 0.3)
        XCTAssertEqual(FloatingWindowConfiguration.normalizedOpacity(0.7), 0.7)
    }

    func testFloatingWindowConfigurationSizesPreviewWindows() throws {
        XCTAssertEqual(
            FloatingWindowConfiguration.preferredWindowSize(for: CGSize(width: 1600, height: 900)),
            CGSize(width: 800, height: 570)
        )
        XCTAssertEqual(
            FloatingWindowConfiguration.preferredWindowSize(for: CGSize(width: 300, height: 120)),
            CGSize(width: 400, height: 300)
        )
        XCTAssertEqual(
            FloatingWindowConfiguration.preferredWindowSize(for: CGSize(width: 4000, height: 4000)),
            CGSize(width: 600, height: 720)
        )
        XCTAssertEqual(
            FloatingWindowConfiguration.preferredWindowSize(for: CGSize(width: 0, height: 400)),
            CGSize(width: 400, height: 300)
        )
    }

    func testFloatingWindowLayoutCentersFirstPinnedWindowAndCascadesMore() throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let windowSize = CGSize(width: 400, height: 300)

        let firstOrigin = FloatingWindowLayout.origin(
            for: windowSize,
            existingWindowFrames: [],
            visibleFrame: visibleFrame
        )
        XCTAssertEqual(firstOrigin, CGPoint(x: 300, y: 200))

        let secondOrigin = FloatingWindowLayout.origin(
            for: windowSize,
            existingWindowFrames: [CGRect(origin: firstOrigin, size: windowSize)],
            visibleFrame: visibleFrame
        )
        XCTAssertEqual(secondOrigin, CGPoint(x: 330, y: 170))
    }

    func testFloatingWindowLayoutKeepsPinnedWindowsInsideVisibleFrame() throws {
        let visibleFrame = CGRect(x: 50, y: 40, width: 500, height: 360)
        let windowSize = CGSize(width: 220, height: 180)
        let existingFrames = [
            CGRect(x: 390, y: 70, width: 220, height: 180),
            CGRect(x: 420, y: 40, width: 220, height: 180),
            CGRect(x: 450, y: 10, width: 220, height: 180)
        ]

        let origin = FloatingWindowLayout.origin(
            for: windowSize,
            existingWindowFrames: existingFrames,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin, CGPoint(x: 330, y: 40))
    }

    func testColorFormatterSupportsHexRgbAndSwiftUIFormats() throws {
        let color = NSColor(srgbRed: 100.0 / 255.0, green: 149.0 / 255.0, blue: 237.0 / 255.0, alpha: 1)

        XCTAssertEqual(ColorCodeFormatter.formattedColorCode(for: color, format: "#HEX"), "#6495ED")
        XCTAssertEqual(ColorCodeFormatter.formattedColorCode(for: color, format: "RGB"), "rgb(100, 149, 237)")
        XCTAssertEqual(
            ColorCodeFormatter.formattedColorCode(for: color, format: "SwiftUI"),
            "Color(red: 0.392, green: 0.584, blue: 0.929)"
        )
    }

    func testColorFormatterSupportsCustomTemplatesAndNames() throws {
        let color = NSColor(srgbRed: 100.0 / 255.0, green: 149.0 / 255.0, blue: 237.0 / 255.0, alpha: 1)

        let formatted = ColorCodeFormatter.formattedColorCode(
            for: color,
            format: "Custom",
            customTemplate: "hex={hex}; rgb={rgb}; channels={r255}/{g255}/{b255}; unit={r},{g},{b}"
        )

        XCTAssertEqual(
            formatted,
            "hex=#6495ED; rgb=rgb(100, 149, 237); channels=100/149/237; unit=0.392,0.584,0.929"
        )
        XCTAssertEqual(ColorCodeFormatter.approximateColorName(for: color), "矢车菊蓝")
    }

    func testColorFormatterParsesHexForScreenshotStyling() throws {
        let color = try XCTUnwrap(ColorCodeFormatter.colorFromHex(" #141414 "))
        let srgb = try XCTUnwrap(color.usingColorSpace(.sRGB))

        XCTAssertEqual(Int(round(srgb.redComponent * 255)), 20)
        XCTAssertEqual(Int(round(srgb.greenComponent * 255)), 20)
        XCTAssertEqual(Int(round(srgb.blueComponent * 255)), 20)
        XCTAssertNil(ColorCodeFormatter.colorFromHex("#12345"))
    }

    func testScrollingImageStitcherTrimsDetectedOverlap() throws {
        let first = makeScrollingTestImage(width: 48, rows: Array(0..<80))
        let second = makeScrollingTestImage(width: 48, rows: Array(48..<128))

        XCTAssertEqual(ScrollingImageStitcher.detectedVerticalOverlap(previous: first, next: second), 32)

        let untrimmed = ScrollingImageStitcher.stitchImagesVertically([first, second], trimOverlap: false)
        let trimmed = ScrollingImageStitcher.stitchImagesVertically([first, second], trimOverlap: true)

        XCTAssertEqual(Int(untrimmed.size.width), 48)
        XCTAssertEqual(Int(untrimmed.size.height), 160)
        XCTAssertEqual(Int(trimmed.size.width), 48)
        XCTAssertEqual(Int(trimmed.size.height), 128)
    }

    func testScrollingImageStitcherPreservesPixelsWithoutWatermark() throws {
        let first = makeSolidImage(width: 12, height: 5, color: .systemRed)
        let second = makeSolidImage(width: 12, height: 4, color: .systemBlue)
        let stitched = ScrollingImageStitcher.stitchImagesVertically([first, second], trimOverlap: false)

        XCTAssertEqual(Int(stitched.size.width), 12)
        XCTAssertEqual(Int(stitched.size.height), 9)

        let pixels = try rgbaPixels(in: stitched)
        var containsRed = false
        var containsBlue = false
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let offset = (y * pixels.width + x) * 4
                let pixel = (
                    red: Int(pixels.buffer[offset]),
                    green: Int(pixels.buffer[offset + 1]),
                    blue: Int(pixels.buffer[offset + 2]),
                    alpha: Int(pixels.buffer[offset + 3])
                )
                let isRedSlice = pixel.red > 180 && pixel.green < 120 && pixel.blue < 120 && pixel.alpha > 240
                let isBlueSlice = pixel.blue > 180 && pixel.red < 120 && pixel.green < 160 && pixel.alpha > 240
                containsRed = containsRed || isRedSlice
                containsBlue = containsBlue || isBlueSlice
                XCTAssertTrue(isRedSlice || isBlueSlice)
            }
        }
        XCTAssertTrue(containsRed)
        XCTAssertTrue(containsBlue)
    }

    func testScrollingImageStitcherOrdersUpwardCapturesByReadingDirection() throws {
        let top = makeScrollingTestImage(width: 8, rows: Array(0..<40))
        let bottom = makeScrollingTestImage(width: 8, rows: Array(40..<80))

        let downOrdered = ScrollingImageStitcher.orderedImages([top, bottom], direction: "down")
        let upOrdered = ScrollingImageStitcher.orderedImages([bottom, top], direction: "up")

        XCTAssertTrue(downOrdered[0] === top)
        XCTAssertTrue(downOrdered[1] === bottom)
        XCTAssertTrue(upOrdered[0] === top)
        XCTAssertTrue(upOrdered[1] === bottom)
    }

    func testScrollingImageStitcherDetectsUnchangedEndFrame() throws {
        let image = makeScrollingTestImage(width: 48, rows: Array(0..<80))
        let changed = makeScrollingTestImage(width: 48, rows: Array(10..<90))

        XCTAssertTrue(ScrollingImageStitcher.imagesAreVisuallySimilar(image, image))
        XCTAssertFalse(ScrollingImageStitcher.imagesAreVisuallySimilar(image, changed))
    }

    func testScrollingCaptureSettingsNormalizeExecutionBounds() throws {
        XCTAssertEqual(ScrollingCaptureSettings.normalizedSliceCount(0), 30)
        XCTAssertEqual(ScrollingCaptureSettings.normalizedSliceCount(1), 2)
        XCTAssertEqual(ScrollingCaptureSettings.normalizedSliceCount(250), 100)

        XCTAssertEqual(ScrollingCaptureSettings.normalizedDelay(0), 0.8)
        XCTAssertEqual(ScrollingCaptureSettings.normalizedDelay(0.05), 0.2)
        XCTAssertEqual(ScrollingCaptureSettings.normalizedDelay(8.0), 2.0)

        XCTAssertEqual(ScrollingCaptureSettings.normalizedScrollLines(0), 12)
        XCTAssertEqual(ScrollingCaptureSettings.normalizedScrollLines(1), 3)
        XCTAssertEqual(ScrollingCaptureSettings.normalizedScrollLines(120), 40)

        XCTAssertEqual(ScrollingCaptureSettings.normalizedDirection("up"), "up")
        XCTAssertEqual(ScrollingCaptureSettings.normalizedDirection("sideways"), "down")
        XCTAssertEqual(ScrollingCaptureSettings.normalizedDirection(nil), "down")
    }

    func testScrollingCaptureSettingsReadNormalizedDefaults() throws {
        let suiteName = "MacScreenCaptureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(1_000, forKey: "scrollingCaptureSlices")
        defaults.set(10.0, forKey: "scrollingCaptureDelay")
        defaults.set(-5, forKey: "scrollingCaptureLines")
        defaults.set("up", forKey: "scrollingCaptureDirection")

        let settings = ScrollingCaptureSettings.fromDefaults(defaults)

        XCTAssertEqual(settings.sliceCount, 100)
        XCTAssertEqual(settings.delay, 2.0)
        XCTAssertEqual(settings.scrollLines, 12)
        XCTAssertEqual(settings.direction, "up")
    }

    func testMultiWindowCompositeLayoutKeepsRelativeWindowPositions() throws {
        let displayBounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let firstWindow = CGRect(x: 100, y: 120, width: 220, height: 160)
        let secondWindow = CGRect(x: 360, y: 260, width: 180, height: 120)

        let outputRect = try XCTUnwrap(MultiWindowCompositeLayout.outputRect(
            for: [firstWindow, secondWindow],
            displayBounds: displayBounds
        ))
        let firstDrawRect = try XCTUnwrap(MultiWindowCompositeLayout.drawRect(for: firstWindow, in: outputRect))
        let secondDrawRect = try XCTUnwrap(MultiWindowCompositeLayout.drawRect(for: secondWindow, in: outputRect))

        XCTAssertEqual(outputRect, CGRect(x: 76, y: 96, width: 488, height: 308))
        XCTAssertEqual(firstDrawRect, CGRect(x: 24, y: 124, width: 220, height: 160))
        XCTAssertEqual(secondDrawRect, CGRect(x: 284, y: 24, width: 180, height: 120))
    }

    func testMultiWindowCompositeLayoutClipsToDisplayBounds() throws {
        let displayBounds = CGRect(x: 0, y: 0, width: 500, height: 400)
        let window = CGRect(x: 430, y: 330, width: 120, height: 100)

        let outputRect = try XCTUnwrap(MultiWindowCompositeLayout.outputRect(
            for: [window],
            displayBounds: displayBounds
        ))
        let drawRect = try XCTUnwrap(MultiWindowCompositeLayout.drawRect(for: window, in: outputRect))

        XCTAssertEqual(outputRect, CGRect(x: 406, y: 306, width: 94, height: 94))
        XCTAssertEqual(drawRect, CGRect(x: 24, y: 0, width: 70, height: 70))
    }

    func testMultiWindowCompositeLayoutCreatesBackdropSegmentsAcrossDisplays() throws {
        let outputRect = CGRect(x: 450, y: 100, width: 220, height: 160)
        let segments = MultiWindowCompositeLayout.backdropSegments(
            for: [
                CGRect(x: 0, y: 0, width: 500, height: 400),
                CGRect(x: 500, y: 0, width: 500, height: 400)
            ],
            outputRect: outputRect
        )

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].visibleRect, CGRect(x: 450, y: 100, width: 50, height: 160))
        XCTAssertEqual(segments[0].drawRect, CGRect(x: 0, y: 0, width: 50, height: 160))
        XCTAssertEqual(segments[1].visibleRect, CGRect(x: 500, y: 100, width: 170, height: 160))
        XCTAssertEqual(segments[1].drawRect, CGRect(x: 50, y: 0, width: 170, height: 160))
    }

    func testScreenshotStyleRendererRoundsCornersToTransparentPixels() throws {
        let image = makeSolidImage(width: 40, height: 40, color: .systemRed)
        let rounded = ScreenshotStyleRenderer.renderRoundedImage(image, radius: 16)

        let corner = try rgbaPixel(in: rounded, x: 0, y: 0)
        let center = try rgbaPixel(in: rounded, x: 20, y: 20)

        XCTAssertLessThan(corner.alpha, 10)
        XCTAssertGreaterThan(center.red, 200)
        XCTAssertGreaterThan(center.alpha, 240)
    }

    func testScreenshotStyleRendererKeepsRoundedShadowCornersTransparent() throws {
        let image = makeSolidImage(width: 40, height: 40, color: .systemBlue)
        let styled = ScreenshotStyleRenderer.applyOutputStyle(
            to: image,
            style: ScreenshotStyleRenderer.OutputStyle(
                roundedCorners: true,
                cornerRadius: 16,
                dropShadow: true,
                shadowRadius: 12,
                shadowColor: .black
            )
        )

        XCTAssertEqual(Int(styled.size.width), 88)
        XCTAssertEqual(Int(styled.size.height), 88)

        let outerCorner = try rgbaPixel(in: styled, x: 0, y: 0)
        let containsBlueImage = try imageContainsPixel(in: styled) { pixel in
            pixel.blue > 150 && pixel.alpha > 240
        }

        XCTAssertLessThan(outerCorner.alpha, 10)
        XCTAssertTrue(containsBlueImage)
    }

    func testScreenshotStyleRendererBuildsDeviceFrameWithoutWatermark() throws {
        let image = makeSolidImage(width: 20, height: 12, color: .white)
        let framed = ScreenshotStyleRenderer.renderDeviceFrame(
            around: image,
            style: ScreenshotStyleRenderer.DeviceFrameStyle(
                bezel: 18,
                padding: 16,
                cornerRadius: 12,
                shadowRadius: 0,
                bodyColor: .black,
                shadowColor: .black
            )
        )

        XCTAssertEqual(Int(framed.size.width), 88)
        XCTAssertEqual(Int(framed.size.height), 104)
        let containsWhiteScreen = try imageContainsPixel(in: framed) { pixel in
            pixel.red > 240 && pixel.green > 240 && pixel.blue > 240 && pixel.alpha > 240
        }
        XCTAssertTrue(containsWhiteScreen)
    }

    func testImageEditingSessionRendersNumberedAnnotationIntoOutputImage() throws {
        let image = makeSolidImage(width: 90, height: 90, color: .white)
        let session = ImageEditingSession(originalImage: image)

        session.addOperation(EditingOperation(
            type: .numbered,
            points: [CGPoint(x: 45, y: 45)],
            color: .systemRed,
            lineWidth: 4,
            text: "7",
            fontSize: 26,
            textOutlined: true
        ))

        let containsRedMarker = try imageContainsPixel(in: session.currentImage) { pixel in
            pixel.red > 200 && pixel.green < 90 && pixel.blue < 90 && pixel.alpha > 240
        }
        let containsWhiteNumberOrBorder = try imageContainsPixel(in: session.currentImage) { pixel in
            pixel.red > 240 && pixel.green > 240 && pixel.blue > 240 && pixel.alpha > 240
        }

        XCTAssertTrue(containsRedMarker)
        XCTAssertTrue(containsWhiteNumberOrBorder)
    }

    func testImageEditingSessionRendersOutlinedTextIntoOutputImage() throws {
        let image = makeSolidImage(width: 180, height: 80, color: .black)
        let session = ImageEditingSession(originalImage: image)

        session.addOperation(EditingOperation(
            type: .text,
            color: .systemGreen,
            lineWidth: 2,
            text: "iShot",
            rect: CGRect(x: 12, y: 18, width: 150, height: 46),
            fontSize: 34,
            textOutlined: true
        ))

        let containsGreenText = try imageContainsPixel(in: session.currentImage) { pixel in
            pixel.green > 140 && pixel.red < 140 && pixel.blue < 140 && pixel.alpha > 200
        }
        let containsWhiteOutline = try imageContainsPixel(in: session.currentImage) { pixel in
            pixel.red > 200 && pixel.green > 200 && pixel.blue > 200 && pixel.alpha > 200
        }

        XCTAssertTrue(containsGreenText)
        XCTAssertTrue(containsWhiteOutline)
    }

    func testOCRTextOrdererSortsByVisualReadingOrder() throws {
        let boxes = [
            makeTextBox("第二行右", x: 0.55, y: 0.40),
            makeTextBox("第一行右", x: 0.60, y: 0.72),
            makeTextBox("第二行左", x: 0.12, y: 0.41),
            makeTextBox("第一行左", x: 0.10, y: 0.70)
        ]

        XCTAssertEqual(
            OCRTextOrderer.joinedText(boxes),
            "第一行左\n第一行右\n第二行左\n第二行右"
        )
    }

    func testOCRTextOrdererKeepsSlightVerticalJitterOnSameLine() throws {
        let boxes = [
            makeTextBox("中", x: 0.40, y: 0.50, height: 0.10),
            makeTextBox("左", x: 0.10, y: 0.54, height: 0.10),
            makeTextBox("右", x: 0.70, y: 0.47, height: 0.10)
        ]

        XCTAssertEqual(
            OCRTextOrderer.sortedTextBoxes(boxes).map(\.text),
            ["左", "中", "右"]
        )
    }

    func testOCRTextOrdererTreatsLargeVerticalGapAsNewLine() throws {
        let boxes = [
            makeTextBox("下方靠左", x: 0.10, y: 0.35, height: 0.08),
            makeTextBox("上方靠右", x: 0.70, y: 0.70, height: 0.08)
        ]

        XCTAssertEqual(
            OCRTextOrderer.sortedTextBoxes(boxes).map(\.text),
            ["上方靠右", "下方靠左"]
        )
    }

    func testEditingOperationPreservesExplicitAnnotationFontSize() throws {
        let operation = EditingOperation(
            type: .numbered,
            points: [CGPoint(x: 20, y: 30)],
            color: .systemRed,
            lineWidth: 2,
            text: "7",
            rect: CGRect(x: 40, y: 50, width: 100, height: 36),
            fontSize: 32,
            textOutlined: true
        )

        let moved = operation.moved(by: CGSize(width: 8, height: -4))
        let renamed = moved.replacingText(with: "8")

        XCTAssertEqual(operation.resolvedAnnotationFontSize, 32)
        XCTAssertEqual(operation.resolvedNumberedMarkerDiameter, max(24, 32 / 0.52), accuracy: 0.001)
        XCTAssertEqual(moved.fontSize, 32)
        XCTAssertEqual(moved.points.first, CGPoint(x: 28, y: 26))
        XCTAssertEqual(moved.rect?.origin, CGPoint(x: 48, y: 46))
        XCTAssertEqual(renamed.text, "8")
        XCTAssertEqual(renamed.fontSize, 32)
        XCTAssertTrue(renamed.textOutlined)
    }

    func testEditingOperationClampsAnnotationFontSizeForRendering() throws {
        let tiny = EditingOperation(type: .text, lineWidth: 1, text: "small", fontSize: 4)
        let huge = EditingOperation(type: .text, lineWidth: 1, text: "large", fontSize: 120)
        let legacy = EditingOperation(type: .text, lineWidth: 3, text: "legacy")

        XCTAssertEqual(tiny.resolvedAnnotationFontSize, 10)
        XCTAssertEqual(huge.resolvedAnnotationFontSize, 72)
        XCTAssertEqual(legacy.resolvedAnnotationFontSize, 24)
    }

    func testTranslationSupportParsesGoogleResponseSegments() throws {
        let data = try XCTUnwrap("""
        [[["你好，","hello,",null,null,1],["世界"," world",null,null,1]],null,"en"]
        """.data(using: .utf8))

        XCTAssertEqual(try TranslationSupport.translatedTextFromGoogleResponse(data), "你好，世界")
    }

    func testTranslationSupportParsesMyMemoryResponse() throws {
        let data = try XCTUnwrap("""
        {"responseData":{"translatedText":"  你好，世界  "},"responseStatus":200}
        """.data(using: .utf8))

        XCTAssertEqual(try TranslationSupport.translatedTextFromMyMemoryResponse(data), "你好，世界")
    }

    func testTranslationSupportRejectsEmptyProviderResponses() throws {
        let emptyGoogle = try XCTUnwrap("[[[\"   \",\"hello\"]]]".data(using: .utf8))
        let emptyMyMemory = try XCTUnwrap("""
        {"responseData":{"translatedText":"   "}}
        """.data(using: .utf8))

        XCTAssertThrowsError(try TranslationSupport.translatedTextFromGoogleResponse(emptyGoogle))
        XCTAssertThrowsError(try TranslationSupport.translatedTextFromMyMemoryResponse(emptyMyMemory))
    }

    func testTranslationSupportBuildsEncodedWebFallbackURL() throws {
        let url = try XCTUnwrap(TranslationSupport.webTranslationURL(for: "hello & 世界", targetLanguage: "zh-CN"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "translate.google.com")
        XCTAssertEqual(queryItems.first { $0.name == "sl" }?.value, "auto")
        XCTAssertEqual(queryItems.first { $0.name == "tl" }?.value, "zh-CN")
        XCTAssertEqual(queryItems.first { $0.name == "text" }?.value, "hello & 世界")
        XCTAssertEqual(queryItems.first { $0.name == "op" }?.value, "translate")
        XCTAssertTrue(url.absoluteString.contains("hello%20%26%20"))
    }

    func testTranslationSupportMapsLanguageCodesForProviders() throws {
        XCTAssertEqual(TranslationSupport.appleLanguageCode(for: "zh-CN"), "zh-Hans")
        XCTAssertEqual(TranslationSupport.appleLanguageCode(for: "zh-TW"), "zh-Hant")
        XCTAssertEqual(TranslationSupport.myMemoryLanguageCode(for: "ja"), "ja")
        XCTAssertEqual(TranslationSupport.displayName(forAppleLanguageCode: "zh-CN"), "简体中文")
    }

    func testRecordingSettingsNormalizePreflightValues() throws {
        XCTAssertEqual(RecordingSettings.normalizedFrameRate(0), 60)
        XCTAssertEqual(RecordingSettings.normalizedFrameRate(12), 15)
        XCTAssertEqual(RecordingSettings.normalizedFrameRate(120), 60)
        XCTAssertEqual(RecordingSettings.normalizedFrameRate(29.6), 30)

        XCTAssertEqual(RecordingSettings.normalizedQuality("超高"), "超高")
        XCTAssertEqual(RecordingSettings.normalizedQuality("invalid"), "高")
        XCTAssertEqual(RecordingSettings.normalizedFileFormat("mp4"), "MP4")
        XCTAssertEqual(RecordingSettings.normalizedFileFormat("avi"), "MOV")
        XCTAssertEqual(RecordingSettings.fileExtension(for: "MP4"), "mp4")
        XCTAssertEqual(RecordingSettings.avFileType(for: "MP4"), .mp4)
        XCTAssertEqual(RecordingSettings.avFileType(for: nil), .mov)
    }

    func testRecordingSettingsScaleBitrateByQualityAndClampBounds() throws {
        let low = RecordingSettings.videoBitRate(width: 1920, height: 1080, frameRate: 60, quality: "低")
        let high = RecordingSettings.videoBitRate(width: 1920, height: 1080, frameRate: 60, quality: "高")
        let ultra = RecordingSettings.videoBitRate(width: 1920, height: 1080, frameRate: 60, quality: "超高")
        let tiny = RecordingSettings.videoBitRate(width: 1, height: 1, frameRate: 15, quality: "低")
        let huge = RecordingSettings.videoBitRate(width: 8_000, height: 8_000, frameRate: 120, quality: "超高")

        XCTAssertLessThan(low, high)
        XCTAssertLessThan(high, ultra)
        XCTAssertEqual(tiny, 2_000_000)
        XCTAssertEqual(huge, 60_000_000)
    }

    func testRecordingAudioSourceSelectionDisablesUnavailableMicrophoneForThisRun() throws {
        let selection = RecordingAudioSourceSelection.resolved(
            includeSystemAudio: true,
            includeMicrophonePreference: true,
            microphoneDeviceAvailable: false,
            microphonePermissionGranted: false
        )

        XCTAssertTrue(selection.includeSystemAudio)
        XCTAssertFalse(selection.includeMicrophone)
        XCTAssertTrue(selection.hasAnySource)
    }

    func testRecordingAudioSourceSelectionRequiresUsableMicrophoneWhenItIsOnlySource() throws {
        let missingDevice = RecordingAudioSourceSelection.resolved(
            includeSystemAudio: false,
            includeMicrophonePreference: true,
            microphoneDeviceAvailable: false,
            microphonePermissionGranted: false
        )
        let deniedPermission = RecordingAudioSourceSelection.resolved(
            includeSystemAudio: false,
            includeMicrophonePreference: true,
            microphoneDeviceAvailable: true,
            microphonePermissionGranted: false
        )
        let usableMicrophone = RecordingAudioSourceSelection.resolved(
            includeSystemAudio: false,
            includeMicrophonePreference: true,
            microphoneDeviceAvailable: true,
            microphonePermissionGranted: true
        )

        XCTAssertFalse(missingDevice.hasAnySource)
        XCTAssertFalse(deniedPermission.hasAnySource)
        XCTAssertTrue(usableMicrophone.includeMicrophone)
        XCTAssertTrue(usableMicrophone.hasAnySource)
    }

    func testRecordingCompletionSummaryReportsSuccessfulSystemAudioCapture() throws {
        let diagnostics = makeRecordingDiagnostics(
            requestedSystemAudio: true,
            requestedMicrophone: false,
            videoFrameCount: 120,
            systemAudioFrameCount: 240,
            videoTrackCount: 1,
            audioTrackCount: 1,
            fileSize: 4_096,
            assetWriterSucceeded: true,
            audioOnly: false
        )

        let summary = RecordingCompletionSummary.make(
            outputURL: URL(fileURLWithPath: "/tmp/test.mov"),
            diagnostics: diagnostics,
            fallbackModeLabel: "全屏"
        )

        XCTAssertEqual(summary.severity, .success)
        XCTAssertEqual(summary.title, "录制已保存")
        XCTAssertEqual(summary.detail, "系统音频 240 帧，音轨 1/1")
        XCTAssertEqual(summary.modeLabel, "全屏")
    }

    func testRecordingCompletionSummarySurfacesMissingSystemAudio() throws {
        let diagnostics = makeRecordingDiagnostics(
            requestedSystemAudio: true,
            requestedMicrophone: false,
            videoFrameCount: 120,
            systemAudioFrameCount: 0,
            videoTrackCount: 1,
            audioTrackCount: 1,
            fileSize: 4_096,
            assetWriterSucceeded: true,
            audioOnly: false
        )

        let summary = RecordingCompletionSummary.make(
            outputURL: URL(fileURLWithPath: "/tmp/test.mov"),
            diagnostics: diagnostics,
            fallbackModeLabel: "窗口"
        )

        XCTAssertEqual(summary.severity, .warning)
        XCTAssertEqual(summary.title, "录制完成，音频需检查")
        XCTAssertEqual(summary.detail, "系统音频 0 帧，音轨 1/1")
        XCTAssertEqual(summary.modeLabel, "窗口")
    }

    func testRecordingCompletionSummaryLabelsAudioOnlyOutput() throws {
        let summary = RecordingCompletionSummary.make(
            outputURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            diagnostics: nil,
            fallbackModeLabel: "全屏"
        )

        XCTAssertEqual(summary.severity, .success)
        XCTAssertEqual(summary.title, "录音已保存")
        XCTAssertEqual(summary.detail, "文件已保存")
        XCTAssertEqual(summary.modeLabel, "仅录音")
    }

    func testIShotInteractionTimingNormalizesDelayAndDoubleOptionWindows() throws {
        XCTAssertEqual(IShotInteractionTiming.delayedScreenshotSeconds(0), 5)
        XCTAssertEqual(IShotInteractionTiming.delayedScreenshotSeconds(-3), 1)
        XCTAssertEqual(IShotInteractionTiming.delayedScreenshotSeconds(45), 30)
        XCTAssertEqual(IShotInteractionTiming.doubleOptionInterval(0), 0.45)
        XCTAssertEqual(IShotInteractionTiming.doubleOptionInterval(0.1), 0.25)
        XCTAssertEqual(IShotInteractionTiming.doubleOptionInterval(2), 1.2)
        XCTAssertEqual(IShotInteractionTiming.doubleOptionCooldown(0), 1.0)
        XCTAssertEqual(IShotInteractionTiming.doubleOptionCooldown(0.1), 0.5)
        XCTAssertEqual(IShotInteractionTiming.doubleOptionCooldown(9), 3.0)
    }

    func testIShotInteractionTimingDetectsDoubleOptionAndCooldown() throws {
        var detector = IShotInteractionTiming.DoubleOptionDetector()
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertFalse(detector.registerPress(at: start, interval: 0.45, cooldown: 1.0))
        XCTAssertTrue(detector.registerPress(at: start.addingTimeInterval(0.30), interval: 0.45, cooldown: 1.0))
        XCTAssertFalse(detector.registerPress(at: start.addingTimeInterval(0.60), interval: 0.45, cooldown: 1.0))
        XCTAssertFalse(detector.registerPress(at: start.addingTimeInterval(1.65), interval: 0.45, cooldown: 1.0))
        XCTAssertTrue(detector.registerPress(at: start.addingTimeInterval(1.90), interval: 0.45, cooldown: 1.0))
    }

    func testIShotInteractionTimingDoesNotTriggerOutsideDoublePressWindow() throws {
        var detector = IShotInteractionTiming.DoubleOptionDetector()
        let start = Date(timeIntervalSince1970: 2_000)

        XCTAssertFalse(detector.registerPress(at: start, interval: 0.45, cooldown: 1.0))
        XCTAssertFalse(detector.registerPress(at: start.addingTimeInterval(0.80), interval: 0.45, cooldown: 1.0))
        XCTAssertTrue(detector.registerPress(at: start.addingTimeInterval(1.00), interval: 0.45, cooldown: 1.0))
    }

    func testNotificationManagerInitialization() throws {
        throw XCTSkip("NotificationManager requires a real app bundle host for UNUserNotificationCenter.")
    }
    
    func testKeyboardShortcutsInitialization() throws {
        let keyboardShortcuts = KeyboardShortcuts.shared
        XCTAssertNotNil(keyboardShortcuts)
    }
    
    func testCaptureErrorEnum() throws {
        let error1 = CaptureError.noDisplayAvailable
        let error2 = CaptureError.noWindowSelected
        let error3 = CaptureError.regionRecordingNotSupported
        let error4 = CaptureError.unsupportedSystem
        let error5 = CaptureError.failedToCapture
        let error6 = CaptureError.failedToSaveImage
        
        XCTAssertEqual(error1.errorDescription, "没有可用的显示器")
        XCTAssertEqual(error2.errorDescription, "没有选择窗口")
        XCTAssertEqual(error3.errorDescription, "区域录制暂不支持")
        XCTAssertEqual(error4.errorDescription, "系统版本不支持")
        XCTAssertEqual(error5.errorDescription, "捕获失败")
        XCTAssertEqual(error6.errorDescription, "保存图片失败")
    }

    func testRecordingDiagnosticsDetectsSilentVideoOutputFailure() throws {
        let diagnostics = makeRecordingDiagnostics(
            requestedSystemAudio: false,
            requestedMicrophone: false,
            videoFrameCount: 0,
            videoTrackCount: 0,
            audioTrackCount: 0,
            fileSize: 0,
            assetWriterSucceeded: false,
            audioOnly: false
        )

        XCTAssertTrue(diagnostics.hasOutputIssue)
        XCTAssertEqual(diagnostics.outputIssueText, "文件写入未成功")
        XCTAssertFalse(diagnostics.hasAudioIssue)
        XCTAssertEqual(diagnostics.summaryText, "静音录制")
    }

    func testRecordingDiagnosticsRequiresRequestedAudioTracks() throws {
        let diagnostics = makeRecordingDiagnostics(
            requestedSystemAudio: true,
            requestedMicrophone: true,
            videoFrameCount: 120,
            systemAudioFrameCount: 240,
            microphoneFrameCount: 0,
            videoTrackCount: 1,
            audioTrackCount: 1,
            fileSize: 1_024,
            assetWriterSucceeded: true,
            audioOnly: false
        )

        XCTAssertFalse(diagnostics.hasOutputIssue)
        XCTAssertTrue(diagnostics.hasAudioIssue)
        XCTAssertEqual(diagnostics.requestedAudioSourceCount, 2)
        XCTAssertEqual(diagnostics.summaryText, "系统音频 240 帧，麦克风 0 帧，音轨 1/2")
    }

    func testRecordingDiagnosticsAcceptsMixedAudioWhenBothSourcesHaveFrames() throws {
        let diagnostics = makeRecordingDiagnostics(
            requestedSystemAudio: true,
            requestedMicrophone: true,
            videoFrameCount: 120,
            systemAudioFrameCount: 240,
            microphoneFrameCount: 180,
            videoTrackCount: 1,
            audioTrackCount: 2,
            fileSize: 4_096,
            assetWriterSucceeded: true,
            audioOnly: false
        )

        XCTAssertFalse(diagnostics.hasOutputIssue)
        XCTAssertFalse(diagnostics.hasAudioIssue)
        XCTAssertEqual(diagnostics.summaryText, "系统音频 240 帧，麦克风 180 帧，音轨 2/2")
    }

    func testRecordingDiagnosticsFlagsMissingAudioTrackWhenBothSourcesWereRequested() throws {
        let diagnostics = makeRecordingDiagnostics(
            requestedSystemAudio: true,
            requestedMicrophone: true,
            videoFrameCount: 120,
            systemAudioFrameCount: 240,
            microphoneFrameCount: 180,
            videoTrackCount: 1,
            audioTrackCount: 1,
            fileSize: 4_096,
            assetWriterSucceeded: true,
            audioOnly: false
        )

        XCTAssertFalse(diagnostics.hasOutputIssue)
        XCTAssertTrue(diagnostics.hasAudioIssue)
        XCTAssertEqual(diagnostics.summaryText, "系统音频 240 帧，麦克风 180 帧，音轨 1/2")
    }

    func testRecordingDiagnosticsAllowsAudioOnlyWithoutVideoTrack() throws {
        let diagnostics = makeRecordingDiagnostics(
            requestedSystemAudio: true,
            requestedMicrophone: false,
            videoFrameCount: 0,
            systemAudioFrameCount: 180,
            videoTrackCount: 0,
            audioTrackCount: 1,
            fileSize: 2_048,
            assetWriterSucceeded: true,
            audioOnly: true
        )

        XCTAssertFalse(diagnostics.hasOutputIssue)
        XCTAssertFalse(diagnostics.hasAudioIssue)
        XCTAssertEqual(diagnostics.summaryText, "系统音频 180 帧，音轨 1/1")
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
            let _ = CaptureManager()
        }
    }

    private func makeRecordingDiagnostics(
        requestedSystemAudio: Bool,
        requestedMicrophone: Bool,
        videoFrameCount: Int,
        systemAudioFrameCount: Int = 0,
        microphoneFrameCount: Int = 0,
        systemAudioFailCount: Int = 0,
        microphoneFailCount: Int = 0,
        videoTrackCount: Int,
        audioTrackCount: Int,
        fileSize: Int64,
        assetWriterSucceeded: Bool,
        audioOnly: Bool
    ) -> RecordingAudioDiagnostics {
        RecordingAudioDiagnostics(
            outputURL: URL(fileURLWithPath: "/tmp/test-recording.mov"),
            requestedSystemAudio: requestedSystemAudio,
            requestedMicrophone: requestedMicrophone,
            videoFrameCount: videoFrameCount,
            systemAudioFrameCount: systemAudioFrameCount,
            microphoneFrameCount: microphoneFrameCount,
            systemAudioFailCount: systemAudioFailCount,
            microphoneFailCount: microphoneFailCount,
            videoTrackCount: videoTrackCount,
            audioTrackCount: audioTrackCount,
            fileSize: fileSize,
            assetWriterSucceeded: assetWriterSucceeded,
            audioOnly: audioOnly
        )
    }

    private func makeScrollingTestImage(width: Int, rows: [Int]) -> NSImage {
        let height = rows.count
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)

        for (y, value) in rows.enumerated() {
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                buffer[offset] = UInt8((value + x) % 256)
                buffer[offset + 1] = UInt8((value * 3 + x) % 256)
                buffer[offset + 2] = UInt8((255 - value + x) % 256)
                buffer[offset + 3] = 255
            }
        }

        let data = Data(buffer)
        let provider = CGDataProvider(data: data as CFData)!
        let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    private func repositoryFileContents(_ relativePath: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = relativePath
            .split(separator: "/")
            .reduce(repositoryRoot) { partialURL, component in
                partialURL.appendingPathComponent(String(component))
            }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func makeSolidImage(width: Int, height: Int, color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
    }

    private func makeTextBox(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 0.20, height: CGFloat = 0.08) -> OCRTextOrderer.TextBox {
        OCRTextOrderer.TextBox(
            text: text,
            boundingBox: CGRect(x: x, y: y, width: width, height: height)
        )
    }

    private func rgbaPixel(in image: NSImage, x: Int, y: Int) throws -> (red: Int, green: Int, blue: Int, alpha: Int) {
        let pixels = try rgbaPixels(in: image)
        XCTAssertTrue((0..<pixels.width).contains(x))
        XCTAssertTrue((0..<pixels.height).contains(y))

        let offset = (y * pixels.width + x) * 4
        return (
            Int(pixels.buffer[offset]),
            Int(pixels.buffer[offset + 1]),
            Int(pixels.buffer[offset + 2]),
            Int(pixels.buffer[offset + 3])
        )
    }

    private func imageContainsPixel(
        in image: NSImage,
        matching predicate: ((red: Int, green: Int, blue: Int, alpha: Int)) -> Bool
    ) throws -> Bool {
        let pixels = try rgbaPixels(in: image)
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let offset = (y * pixels.width + x) * 4
                let pixel = (
                    red: Int(pixels.buffer[offset]),
                    green: Int(pixels.buffer[offset + 1]),
                    blue: Int(pixels.buffer[offset + 2]),
                    alpha: Int(pixels.buffer[offset + 3])
                )
                if predicate(pixel) {
                    return true
                }
            }
        }
        return false
    }

    private func rgbaPixels(in image: NSImage) throws -> (width: Int, height: Int, buffer: [UInt8]) {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let width = cgImage.width
        let height = cgImage.height

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        let context = try XCTUnwrap(CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (width, height, buffer)
    }
}
