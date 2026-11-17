import Foundation

@available(macOS 12.3, *)
final class BackgroundResponsivenessManager {
    static let shared = BackgroundResponsivenessManager()

    private let beginActivity: (ProcessInfo.ActivityOptions, String) -> NSObjectProtocol
    private let endActivity: (NSObjectProtocol) -> Void
    private var lastHotKeyUptimeNanoseconds: UInt64?
    private let stateLock = NSLock()

    init(
        beginActivity: @escaping (ProcessInfo.ActivityOptions, String) -> NSObjectProtocol = {
            ProcessInfo.processInfo.beginActivity(options: $0, reason: $1)
        },
        endActivity: @escaping (NSObjectProtocol) -> Void = {
            ProcessInfo.processInfo.endActivity($0)
        }
    ) {
        self.beginActivity = beginActivity
        self.endActivity = endActivity
    }

    func hotKeyWakeMetadata() -> [String: String] {
        stateLock.lock()
        defer { stateLock.unlock() }
        let now = DispatchTime.now().uptimeNanoseconds
        let previous = lastHotKeyUptimeNanoseconds
        lastHotKeyUptimeNanoseconds = now

        // Observe actual events instead of waking the idle app for diagnostics.
        let gap = previous.map { String(format: "%.2f", Double(now - $0) / 1_000_000) }
        return ["previous_hotkey_gap_ms": gap ?? "none"]
    }

    func performHotKeyActivity<T>(_ operation: () async throws -> T) async rethrows -> T {
        let activity = beginActivity(
            [
                .userInitiatedAllowingIdleSystemSleep,
                .automaticTerminationDisabled,
                .suddenTerminationDisabled
            ],
            "Perform a user-requested screenshot hotkey action."
        )

        defer {
            endActivity(activity)
        }

        return try await operation()
    }
}
