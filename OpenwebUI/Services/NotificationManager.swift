import UserNotifications

/// Sends macOS system notifications for key events.
@MainActor
final class NotificationManager {
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    func sendServerReady(url: String) {
        send(
            title: String(localized: "notification.connected.title"),
            body: String(format: String(localized: "notification.connected.body"), url),
            identifier: "server-ready"
        )
    }

    func sendServerUnreachable(url: String) {
        send(
            title: String(localized: "notification.unreachable.title"),
            body: String(format: String(localized: "notification.unreachable.body"), url),
            identifier: "server-unreachable"
        )
    }

    // MARK: - Private

    private func send(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[NotificationManager] Failed to send notification: \(error)")
            }
        }
    }
}
