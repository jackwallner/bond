import CoreLocation
import Foundation
import UserNotifications

@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private init() {}

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func reschedule(forSelfUserId selfId: UUID, reminders: [ReminderDTO]) async {
        await requestAuthorizationIfNeeded()

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        for reminder in reminders where reminder.targetId == selfId {
            await schedule(reminder)
        }
    }

    private func schedule(_ reminder: ReminderDTO) async {
        guard let trigger = makeTrigger(for: reminder) else { return }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        if let body = reminder.body, !body.isEmpty {
            content.body = body
        }
        content.sound = .default
        content.userInfo = [
            "reminder_id": reminder.id.uuidString,
            "couple_id":  reminder.coupleId.uuidString,
            "love_language": reminder.loveLanguage.rawValue
        ]
        content.threadIdentifier = reminder.loveLanguage.rawValue

        let request = UNNotificationRequest(
            identifier: reminder.id.uuidString,
            content: content,
            trigger: trigger
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    private func makeTrigger(for reminder: ReminderDTO) -> UNNotificationTrigger? {
        switch reminder.trigger {
        case .oneTime(let fireAt):
            guard fireAt > .now else { return nil }
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fireAt
            )
            return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        case .recurring(let rrule, let nextFire):
            guard let preset = RecurrencePreset(rrule: rrule) else { return nil }
            let comps = recurrenceComponents(for: preset, anchor: nextFire)
            return UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        case .location(let geofence, let onEntry):
            let center = CLLocationCoordinate2D(
                latitude: geofence.latitude, longitude: geofence.longitude
            )
            let region = CLCircularRegion(
                center: center,
                radius: geofence.radiusMeters,
                identifier: "bond.\(reminder.id.uuidString)"
            )
            region.notifyOnEntry = onEntry
            region.notifyOnExit = !onEntry
            return UNLocationNotificationTrigger(region: region, repeats: false)

        case .randomWindow:
            // fireAt was already randomized at save time — schedule as one-time.
            guard let fireAt = reminder.fireAt, fireAt > .now else { return nil }
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fireAt
            )
            return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        case .none:
            return nil
        }
    }

    private func recurrenceComponents(
        for preset: RecurrencePreset, anchor: Date
    ) -> DateComponents {
        let cal = Calendar.current
        switch preset {
        case .daily:
            return cal.dateComponents([.hour, .minute], from: anchor)
        case .weekly:
            return cal.dateComponents([.weekday, .hour, .minute], from: anchor)
        case .monthly:
            return cal.dateComponents([.day, .hour, .minute], from: anchor)
        case .yearly:
            return cal.dateComponents([.month, .day, .hour, .minute], from: anchor)
        }
    }
}
