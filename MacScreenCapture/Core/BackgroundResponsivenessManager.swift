import Foundation

@available(macOS 12.3, *)
final class BackgroundResponsivenessManager {
    static let shared = BackgroundResponsivenessManager()

    private var activity: NSObjectProtocol?
    private let processInfo = ProcessInfo.processInfo
    private var readinessHeartbeatTimer: DispatchSourceTimer?
    private var lastReadinessHeartbeatUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
    private let heartbeatQueue = DispatchQueue(label: "com.blademainer.MacScreenCapture.background-readiness-heartbeat", qos: .utility)
    private let stateLock = NSLock()

    private init() {}

    func start() {
        guard activity == nil else { return }

        recordReadinessHeartbeat()
        activity = processInfo.beginActivity(
            options: [
                .userInitiatedAllowingIdleSystemSleep,
                .latencyCritical,
                .automaticTerminationDisabled,
                .suddenTerminationDisabled
            ],
            reason: "Keep screenshot hotkeys responsive while MacScreenCapture is running."
        )
        startReadinessHeartbeat()
    }

    func stop() {
        guard let activity else { return }

        stopReadinessHeartbeat()
        processInfo.endActivity(activity)
        self.activity = nil
    }

    func hotKeyWakeMetadata() -> [String: String] {
        [
            "heartbeat_gap_ms": String(format: "%.2f", readinessHeartbeatGapMilliseconds())
        ]
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

    private func startReadinessHeartbeat() {
        guard readinessHeartbeatTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: heartbeatQueue)
        timer.schedule(deadline: .now(), repeating: .seconds(5), leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            self?.recordReadinessHeartbeat()
        }
        readinessHeartbeatTimer = timer
        timer.resume()
    }

    private func stopReadinessHeartbeat() {
        readinessHeartbeatTimer?.cancel()
        readinessHeartbeatTimer = nil
    }

    private func recordReadinessHeartbeat() {
        stateLock.lock()
        lastReadinessHeartbeatUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        stateLock.unlock()
    }

    private func readinessHeartbeatGapMilliseconds() -> Double {
        stateLock.lock()
        let lastHeartbeat = lastReadinessHeartbeatUptimeNanoseconds
        stateLock.unlock()

        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - lastHeartbeat
        return Double(elapsedNanoseconds) / 1_000_000
    }
}
