//
//  MacScreenCaptureTests.swift
//  MacScreenCaptureTests
//
//  Created by Developer on 2025/9/25.
//

import XCTest
@testable import MacScreenCapture

final class MacScreenCaptureTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testPermissionManagerInitialization() throws {
        let permissionManager = PermissionManager()
        XCTAssertNotNil(permissionManager)
        XCTAssertFalse(permissionManager.permissionCheckInProgress)
    }
    
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
    
    func testNotificationManagerInitialization() throws {
        let notificationManager = NotificationManager.shared
        XCTAssertNotNil(notificationManager)
        XCTAssertTrue(notificationManager.notificationsEnabled)
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

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
            let _ = CaptureManager()
        }
    }
}