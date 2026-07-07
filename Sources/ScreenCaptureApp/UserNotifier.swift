import AppKit
import UserNotifications

@MainActor
final class UserNotifier {
    static let shared = UserNotifier()

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func success(title: String, message: String, fileURL: URL? = nil) {
        show(title: title, message: message)
        if let fileURL, AppPreferences.shared.openAfterCapture {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
    }

    func info(title: String, message: String) {
        show(title: title, message: message)
    }

    func error(_ error: Error) {
        show(title: "Screen Capture", message: error.localizedDescription)
    }

    private func show(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
