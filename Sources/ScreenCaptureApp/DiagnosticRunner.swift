import AppKit
import Foundation

@MainActor
enum DiagnosticRunner {
    static func run(arguments: [String]) async -> Int32 {
        let outputDirectory = diagnosticOutputDirectory(arguments: arguments)
        let includeRecording = arguments.contains("--recording")
        let includeMenu = arguments.contains("--menu")

        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            print("diagnose: cannot create output directory: \(error.localizedDescription)")
            return 2
        }

        let screenshotURL = outputDirectory.appendingPathComponent("diagnostic-screenshot.png")
        switch runScreencapture(outputURL: screenshotURL) {
        case .success:
            print("diagnose: screenshot ok: \(screenshotURL.path)")
        case .failure(let error):
            print("diagnose: screenshot failed: \(error.localizedDescription)")
            return 3
        }

        if includeRecording {
            print("diagnose: screen permission preflight: \(PermissionService.hasScreenRecordingPermission)")
            print("diagnose: NSScreen count: \(NSScreen.screens.count)")

            guard PermissionService.hasScreenRecordingPermission else {
                print("diagnose: recording skipped, Screen Recording permission is not granted for this app identity")
                return 4
            }

            let recordingURL = outputDirectory.appendingPathComponent("diagnostic-recording.mov")
            let areaRecordingURL = outputDirectory.appendingPathComponent("diagnostic-area-recording.mov")
            do {
                try? FileManager.default.removeItem(at: recordingURL)
                try? FileManager.default.removeItem(at: areaRecordingURL)
                try await RecordingDiagnostics.recordFullScreen(outputURL: recordingURL, duration: 2)
                guard fileIsUsable(recordingURL) else {
                    print("diagnose: recording failed: output file is missing or empty")
                    return 5
                }
                print("diagnose: recording ok: \(recordingURL.path)")

                try await RecordingDiagnostics.recordSelectedArea(outputURL: areaRecordingURL, duration: 1)
                guard fileIsUsable(areaRecordingURL) else {
                    print("diagnose: area recording failed: output file is missing or empty")
                    return 5
                }
                print("diagnose: area recording ok: \(areaRecordingURL.path)")
            } catch {
                print("diagnose: recording failed: \(error.localizedDescription)")
                return 5
            }
        } else {
            print("diagnose: recording skipped; pass --recording to run a short recording")
        }

        if includeMenu {
            let menuResult = validateMenu()
            switch menuResult {
            case .success(let count):
                print("diagnose: menu ok: \(count) items")
            case .failure(let error):
                print("diagnose: menu failed: \(error.localizedDescription)")
                return 6
            }
        }

        return 0
    }

    private static func diagnosticOutputDirectory(arguments: [String]) -> URL {
        if let index = arguments.firstIndex(of: "--output"), arguments.indices.contains(index + 1) {
            return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("screen-capture-diagnostics", isDirectory: true)
    }

    private static func runScreencapture(outputURL: URL) -> Result<Void, Error> {
        try? FileManager.default.removeItem(at: outputURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-t", "png", outputURL.path]
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0, fileIsUsable(outputURL) else {
                return .failure(CaptureError.cannotCreateOutput)
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private static func fileIsUsable(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return false
        }
        return size > 0
    }

    private static func validateMenu() -> Result<Int, Error> {
        let delegate = AppDelegate()
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let titles = delegate.diagnosticMenuTitles()
        let required = [
            "Full Screenshot",
            "Full Screenshot in 5 Seconds",
            "Select Area Screenshot",
            "Window Screenshot",
            "Copy Full Screen to Clipboard",
            "Copy Area to Clipboard",
            "Copy Window to Clipboard",
            "Start Full Screen Recording",
            "Start Area Recording",
            "Stop Recording",
            "Open Save Folder",
            "Reveal Last Capture",
            "Show Cursor in Full Screenshot",
            "Reveal File After Capture",
            "Show Clicks in Recording",
            "Request Screen Permission",
            "Open Screen Recording Settings",
            "Quit Screen Capture"
        ]

        let missing = required.filter { !titles.contains($0) }
        if missing.isEmpty {
            return .success(titles.count)
        }
        return .failure(CaptureError.commandFailed("Missing menu items: \(missing.joined(separator: ", "))"))
    }
}
