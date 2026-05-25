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
        // Preserve milestone.* notifications so the milestones scheduler can
        // own them independently of reminder churn.
        let pending = await center.pendingNotificationRequests()
        let toRemove = pending
            .map(\.identifier)
            .filter { !$0.hasPrefix("milestone.") }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)

        for reminder in reminders where reminder.targetId == selfId {
            await schedule(reminder)
        }
    }

    /// Re-schedules local notifications for milestones. Each milestone fires
    /// up to three pings: 7 days before, 1 day before, and on the day at 9am
    /// local. Identifiers are namespaced "milestone.<id>.<offset>" so the
    /// reminder scheduler can leave them alone.
    func rescheduleMilestones(_ milestones: [MilestoneDTO]) async {
        await requestAuthorizationIfNeeded()

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let toRemove = pending
            .map(\.identifier)
            .filter { $0.hasPrefix("milestone.") }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)

        for milestone in milestones {
            await scheduleMilestone(milestone)
        }
    }

    private func scheduleMilestone(_ milestone: MilestoneDTO) async {
        let calendar = Calendar.current
        let occurrence = milestone.nextOccurrence()
        let dayStart = calendar.startOfDay(for: occurrence)
        guard let fireOn = calendar.date(byAdding: .hour, value: 9, to: dayStart) else { return }

        let offsets: [(days: Int, label: String)] = [
            (-7, "in 1 week"),
            (-1, "tomorrow"),
            (0,  "today")
        ]

        let title = milestone.label?.isEmpty == false
            ? milestone.label!
            : milestone.kind.capitalized

        for (days, when) in offsets {
            guard let fireDate = calendar.date(byAdding: .day, value: days, to: fireOn),
                  fireDate > .now
            else { continue }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = "\(title) is \(when)."
            content.sound = .default
            content.threadIdentifier = "milestone"
            content.userInfo = [
                "milestone_id": milestone.id.uuidString,
                "couple_id":    milestone.coupleId.uuidString
            ]

            let comps = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

            let request = UNNotificationRequest(
                identifier: "milestone.\(milestone.id.uuidString).\(days)",
                content: content,
                trigger: trigger
            )
            try? await UNUserNotificationCenter.current().add(request)
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
