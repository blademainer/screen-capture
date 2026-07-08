import Cocoa

enum SystemNotificationPresenter {
    static var canDeliverSystemNotification: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static func deliverLegacy(title: String = "MacScreenCapture", message: String) {
        guard canDeliverSystemNotification else {
            print("\(title): \(message)")
            return
        }

        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message
        notification.soundName = NSUserNotificationDefaultSoundName

        NSUserNotificationCenter.default.deliver(notification)
    }
}
