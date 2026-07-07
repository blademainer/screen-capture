import Foundation

@MainActor
final class AppPreferences {
    static let shared = AppPreferences()

    enum Keys {
        static let outputDirectory = "outputDirectory"
        static let showCursor = "showCursor"
        static let openAfterCapture = "openAfterCapture"
        static let showRecordingClicks = "showRecordingClicks"
    }

    private let defaults = UserDefaults.standard

    var outputDirectory: URL {
        get {
            if let path = defaults.string(forKey: Keys.outputDirectory), !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
        }
        set {
            defaults.set(newValue.path, forKey: Keys.outputDirectory)
        }
    }

    var showCursor: Bool {
        get {
            defaults.object(forKey: Keys.showCursor) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: Keys.showCursor)
        }
    }

    var openAfterCapture: Bool {
        get {
            defaults.object(forKey: Keys.openAfterCapture) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: Keys.openAfterCapture)
        }
    }

    var showRecordingClicks: Bool {
        get {
            defaults.object(forKey: Keys.showRecordingClicks) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: Keys.showRecordingClicks)
        }
    }
}
