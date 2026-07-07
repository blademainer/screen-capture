import Foundation

enum CaptureError: LocalizedError {
    case permissionDenied
    case cancelled
    case commandFailed(String)
    case noDisplay
    case cannotCreateOutput
    case recorderAlreadyRunning
    case recorderNotRunning
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required."
        case .cancelled:
            return "Capture cancelled."
        case .commandFailed(let detail):
            return detail.isEmpty ? "Capture command failed." : detail
        case .noDisplay:
            return "No display is available."
        case .cannotCreateOutput:
            return "Could not create the output file."
        case .recorderAlreadyRunning:
            return "A recording is already running."
        case .recorderNotRunning:
            return "No recording is running."
        case .unsupported(let message):
            return message
        }
    }
}
