import Foundation

enum CaptureKind: String {
    case screenshot = "Screenshot"
    case recording = "Recording"
}

struct FileNamer {
    static func outputURL(kind: CaptureKind, directory: URL, extension fileExtension: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = "\(kind.rawValue) \(formatter.string(from: Date())).\(fileExtension)"
        return directory.appendingPathComponent(name, isDirectory: false)
    }
}
