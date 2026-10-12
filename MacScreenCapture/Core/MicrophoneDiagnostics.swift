import Foundation
import OSLog

final class MicrophoneDiagnostics: @unchecked Sendable {
    static let shared = MicrophoneDiagnostics()
    static var logFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacScreenCapture", isDirectory: true)
            .appendingPathComponent("microphone-debug.log")
    }

    private let queue = DispatchQueue(label: "com.blademainer.MacScreenCapture.microphone-diagnostics", qos: .utility)
    private let logger = Logger(subsystem: "com.blademainer.MacScreenCapture", category: "MicrophoneDiagnostics")
    private let writeRecord: @Sendable (Data) throws -> Void
    private let maxPendingRecords: Int
    private let pendingLock = NSLock()
    private var pendingRecords = 0

    convenience init(logURL: URL = MicrophoneDiagnostics.logFileURL, maxLogBytes: Int = 512 * 1024) {
        let maxLogBytes = max(1, maxLogBytes)
        self.init { data in
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = Data(data.prefix(max(1, maxLogBytes)))
            let attributes = try? fileManager.attributesOfItem(atPath: logURL.path)
            let size = attributes?[.size] as? Int ?? 0
            if size > maxLogBytes - data.count {
                try fileManager.removeItem(at: logURL)
            }

            if fileManager.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        }
    }

    init(maxPendingRecords: Int = 256, writeRecord: @escaping @Sendable (Data) throws -> Void) {
        self.maxPendingRecords = max(1, maxPendingRecords)
        self.writeRecord = writeRecord
    }

    @discardableResult
    func append(_ message: String, level: String = "INFO") -> Bool {
        let date = Date()
        pendingLock.lock()
        defer { pendingLock.unlock() }
        // A stalled diagnostic destination must never accumulate unbounded work.
        guard pendingRecords < maxPendingRecords else { return false }
        pendingRecords += 1
        queue.async {
            defer {
                self.pendingLock.lock()
                self.pendingRecords -= 1
                self.pendingLock.unlock()
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            let line = "[\(formatter.string(from: date))] [\(level)] \(message)\n"
            do {
                try self.writeRecord(Data(line.utf8))
            } catch {
                self.logger.error("microphone_log_write_failed error=\(error.localizedDescription, privacy: .public)")
            }
        }
        return true
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }
}
