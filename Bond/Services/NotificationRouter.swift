import Foundation
import UserNotifications

/// Receives notification taps and surfaces the reminder id so the UI can
/// deep-link into the editor. Without this, `userInfo["reminder_id"]` is set
/// on every scheduled notification but tapping a Bond banner just opens the
/// last-active screen - breaking the nudge-to-act loop the product depends on.
@MainActor
@Observable
final class NotificationRouter: NSObject {
    static let shared = NotificationRouter()

    /// Set when the user taps a notification. Views observe and clear after
    /// presenting the editor.
    var pendingReminderId: UUID?

    private override init() { super.init() }

    /// Wire the system delegate. Call once at app launch.
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }
}

extension NotificationRouter: UNUserNotificationCenterDelegate {
    /// Show banners + play sound when the app is already foregrounded.
    /// Without this iOS suppresses local notifications while the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let raw = userInfo["reminder_id"] as? String
        let id = raw.flatMap(UUID.init(uuidString:))
        completionHandler()
        Task { @MainActor in
            NotificationRouter.shared.pendingReminderId = id
        }
    }
}
