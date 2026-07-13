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
    private static let persistentLogQueue = DispatchQueue(label: "com.blademainer.MacScreenCapture.hotkey-latency-diagnostics", qos: .utility)
    private static let maxPersistentLogBytes: UInt64 = 512 * 1024

    static func makeTrace(action: String) -> HotKeyLatencyTrace {
        HotKeyLatencyTrace(action: action)
    }

    static func mark(_ event: String, metadata: [String: String] = [:]) {
        guard let current else { return }
        let elapsedMilliseconds = current.elapsedMilliseconds()
        let metadataSuffix = metadata.isEmpty
            ? ""
            : " " + metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")

        logger.info(
            "hotkey_latency id=\(current.id, privacy: .public) action=\(current.action, privacy: .public) event=\(event, privacy: .public) elapsed_ms=\(elapsedMilliseconds, privacy: .public)\(metadataSuffix, privacy: .public)"
        )
        appendPersistentRecord(trace: current, event: event, elapsedMilliseconds: elapsedMilliseconds, metadataSuffix: metadataSuffix)
    }

    private static func appendPersistentRecord(trace: HotKeyLatencyTrace, event: String, elapsedMilliseconds: Double, metadataSuffix: String) {
        persistentLogQueue.async {
            do {
                let fileManager = FileManager.default
                let logURL = persistentLogURL()
                try fileManager.createDirectory(
                    at: logURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                if let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
                   let fileSize = attributes[.size] as? UInt64,
                   fileSize > maxPersistentLogBytes {
                    try? fileManager.removeItem(at: logURL)
                }

                let line = "\(ISO8601DateFormatter().string(from: Date())) hotkey_latency id=\(trace.id) action=\(trace.action) event=\(event) elapsed_ms=\(String(format: "%.2f", elapsedMilliseconds))\(metadataSuffix)\n"
                let data = Data(line.utf8)

                if fileManager.fileExists(atPath: logURL.path) {
                    let handle = try FileHandle(forWritingTo: logURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: logURL, options: .atomic)
                }
            } catch {
                logger.error("failed_to_append_hotkey_latency_record error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func persistentLogURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("MacScreenCapture", isDirectory: true)
            .appendingPathComponent("hotkey-latency.log")
    }
}
