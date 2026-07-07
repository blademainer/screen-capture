//
//  MacScreenCaptureTests.swift
//  MacScreenCaptureTests
//
//  Created by Developer on 2025/9/25.
//

import XCTest
import AppKit
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
        XCTAssertEqual(defaults["scrollingCaptureDetectContentArea"] as? Bool, true)
        XCTAssertEqual(defaults["floatingWindowAlwaysOnTop"] as? Bool, true)
        XCTAssertEqual(defaults["doubleOptionQuickOpenEnabled"] as? Bool, true)
        XCTAssertEqual(defaults["annotationStylePreset"] as? String, AnnotationStylePreset.professional.rawValue)
        XCTAssertEqual(defaults["colorCodeFormat"] as? String, "#HEX")
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
}
