import Foundation
import OSLog

@available(macOS 12.3, *)
struct HotKeyLatencyTrace: Sendable {
    let id: String
    let action: String
    private let startUptimeNanoseconds: UInt64

    init(action: String) {
        self.id = UUID().uuidString
        self.action = action
        self.startUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
    }

    func elapsedMilliseconds() -> Double {
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startUptimeNanoseconds
        return Double(elapsedNanoseconds) / 1_000_000
    }
}

@available(macOS 12.3, *)
enum HotKeyLatencyDiagnostics {
    @TaskLocal static var current: HotKeyLatencyTrace?

    private static let logger = Logger(
        subsystem: "com.blademainer.MacScreenCapture",
        category: "HotKeyLatency"
    )

    static func makeTrace(action: String) -> HotKeyLatencyTrace {
        HotKeyLatencyTrace(action: action)
    }

    static func mark(_ event: String) {
        guard let current else { return }

        logger.info(
            "hotkey_latency id=\(current.id, privacy: .public) action=\(current.action, privacy: .public) event=\(event, privacy: .public) elapsed_ms=\(current.elapsedMilliseconds(), privacy: .public)"
        )
    }
}
