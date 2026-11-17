import XCTest
@testable import MacScreenCapture

final class BackgroundResponsivenessTests: XCTestCase {
    func testIdleDiagnosticsDoNotAcquireActivity() {
        var acquisitions = 0
        let manager = BackgroundResponsivenessManager(beginActivity: { _, _ in
            acquisitions += 1
            return NSObject()
        }, endActivity: { _ in
            XCTFail("No idle activity should need releasing")
        })

        XCTAssertEqual(manager.hotKeyWakeMetadata()["previous_hotkey_gap_ms"], "none")
        let gap = manager.hotKeyWakeMetadata()["previous_hotkey_gap_ms"].flatMap(Double.init)
        XCTAssertNotNil(gap)
        XCTAssertGreaterThanOrEqual(gap ?? -1, 0)
        XCTAssertEqual(acquisitions, 0)
    }

    func testHotKeyActivityEndsAfterSuccess() async {
        let token = NSObject()
        var active = false
        var releases = 0
        let manager = BackgroundResponsivenessManager(beginActivity: { options, _ in
            XCTAssertTrue(options.contains(.userInitiatedAllowingIdleSystemSleep))
            XCTAssertFalse(options.contains(.latencyCritical))
            active = true
            return token
        }, endActivity: { activity in
            XCTAssertTrue((activity as AnyObject) === token)
            active = false
            releases += 1
        })

        let value = await manager.performHotKeyActivity {
            XCTAssertTrue(active)
            await Task.yield()
            XCTAssertTrue(active)
            return 42
        }
        XCTAssertEqual(value, 42)
        XCTAssertFalse(active)
        XCTAssertEqual(releases, 1)
    }

    func testHotKeyActivityEndsAfterFailure() async {
        enum Failure: Error { case capture }
        var releases = 0
        let manager = BackgroundResponsivenessManager(beginActivity: { _, _ in
            NSObject()
        }, endActivity: { _ in
            releases += 1
        })

        do {
            try await manager.performHotKeyActivity {
                throw Failure.capture
            }
            XCTFail("Capture error must propagate")
        } catch Failure.capture {
            XCTAssertEqual(releases, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
