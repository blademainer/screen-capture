import Foundation

@available(macOS 12.3, *)
final class BackgroundResponsivenessManager {
    static let shared = BackgroundResponsivenessManager()

    private var activity: NSObjectProtocol?
    private let processInfo = ProcessInfo.processInfo

    private init() {}

    func start() {
        guard activity == nil else { return }

        activity = processInfo.beginActivity(
            options: [
                .automaticTerminationDisabled,
                .suddenTerminationDisabled
            ],
            reason: "Keep screenshot hotkeys responsive while MacScreenCapture is running."
        )
    }

    func stop() {
        guard let activity else { return }

        processInfo.endActivity(activity)
        self.activity = nil
    }

    func performHotKeyActivity<T>(_ operation: () async throws -> T) async rethrows -> T {
        let activity = processInfo.beginActivity(
            options: [
                .userInitiatedAllowingIdleSystemSleep,
                .latencyCritical,
                .automaticTerminationDisabled,
                .suddenTerminationDisabled
            ],
            reason: "Respond to a screenshot hotkey without background wake latency."
        )

        defer {
            processInfo.endActivity(activity)
        }

        return try await operation()
    }
}
