import Foundation

@MainActor
enum ScreenshotMode {
    case fullScreen
    case fullScreenDelayed(seconds: Int)
    case selectedArea
    case selectedWindow
    case clipboardFullScreen
    case clipboardArea
    case clipboardWindow
}

@MainActor
final class ScreenshotService {
    private let preferences: AppPreferences

    init(preferences: AppPreferences = .shared) {
        self.preferences = preferences
    }

    func capture(_ mode: ScreenshotMode, completion: @escaping @MainActor @Sendable (Result<URL?, Error>) -> Void) {
        let directory = preferences.outputDirectory
        let outputURL = FileNamer.outputURL(kind: .screenshot, directory: directory, extension: "png")
        var arguments = ["-t", "png"]

        switch mode {
        case .fullScreen:
            if preferences.showCursor {
                arguments.append("-C")
            }
            arguments.append(outputURL.path)
        case .fullScreenDelayed(let seconds):
            if preferences.showCursor {
                arguments.append("-C")
            }
            arguments.append(contentsOf: ["-T", String(max(1, seconds)), outputURL.path])
        case .selectedArea:
            arguments.append(contentsOf: ["-i", outputURL.path])
        case .selectedWindow:
            arguments.append(contentsOf: ["-i", "-W", outputURL.path])
        case .clipboardFullScreen:
            if preferences.showCursor {
                arguments.append("-C")
            }
            arguments.append("-c")
        case .clipboardArea:
            arguments.append(contentsOf: ["-i", "-c"])
        case .clipboardWindow:
            arguments.append(contentsOf: ["-i", "-W", "-c"])
        }

        runScreencapture(arguments: arguments) { result in
            switch result {
            case .success:
                if mode.isClipboardCapture {
                    completion(.success(nil))
                    return
                }

                guard FileManager.default.fileExists(atPath: outputURL.path) else {
                    completion(.failure(CaptureError.cancelled))
                    return
                }
                completion(.success(outputURL))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func runScreencapture(arguments: [String], completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = arguments

            let stderr = Pipe()
            process.standardError = stderr

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    await MainActor.run { completion(.success(())) }
                } else {
                    let data = stderr.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: data, encoding: .utf8) ?? ""
                    await MainActor.run { completion(.failure(CaptureError.commandFailed(message))) }
                }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }
}

private extension ScreenshotMode {
    var isClipboardCapture: Bool {
        switch self {
        case .clipboardFullScreen, .clipboardArea, .clipboardWindow:
            return true
        case .fullScreen, .fullScreenDelayed, .selectedArea, .selectedWindow:
            return false
        }
    }
}
