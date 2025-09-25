//
//  MacScreenCaptureUITests.swift
//  MacScreenCaptureUITests
//
//  Created by Developer on 2025/9/25.
//

import XCTest

final class MacScreenCaptureUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it's important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
    
    func testMainWindowElements() throws {
        let app = XCUIApplication()
        app.launch()
        
        // 检查主要UI元素是否存在
        XCTAssertTrue(app.staticTexts["Mac Screen Capture"].exists)
        XCTAssertTrue(app.buttons["截图"].exists)
        XCTAssertTrue(app.buttons["录制"].exists)
        XCTAssertTrue(app.buttons["设置"].exists)
    }
    
    func testScreenshotTab() throws {
        let app = XCUIApplication()
        app.launch()
        
        // 点击截图标签
        app.buttons["截图"].click()
        
        // 检查截图相关元素
        XCTAssertTrue(app.staticTexts["截图模式"].exists)
        XCTAssertTrue(app.buttons["开始截图"].exists)
    }
    
    func testRecordingTab() throws {
        let app = XCUIApplication()
        app.launch()
        
        // 点击录制标签
        app.buttons["录制"].click()
        
        // 检查录制相关元素
        XCTAssertTrue(app.staticTexts["录制模式"].exists)
        XCTAssertTrue(app.buttons["开始录制"].exists)
    }
    
    func testSettingsTab() throws {
        let app = XCUIApplication()
        app.launch()
        
        // 点击设置标签
        app.buttons["设置"].click()
        
        // 检查设置相关元素
        XCTAssertTrue(app.staticTexts["权限状态"].exists)
        XCTAssertTrue(app.staticTexts["截图设置"].exists)
        XCTAssertTrue(app.staticTexts["录制设置"].exists)
    }
}