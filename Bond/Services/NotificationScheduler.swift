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

    /// - Parameter requestAuthIfNeeded: when true (default) and authorization is
    ///   still undetermined, this surfaces the system permission prompt. The
    ///   first-launch home load passes `false` so the pre-permission primer
    ///   (`NotificationPrimerSheet`) gets to explain *why* before the bare iOS
    ///   dialog appears — otherwise the primer's `.notDetermined` guard never
    ///   passes and the primer is effectively dead.
    /// - Parameter events: completion events, so a handled one-shot stops
    ///   pinging and a daily-random reminder completed today skips today's
    ///   occurrence. Callers without event access may pass `[]`.
    func reschedule(
        forSelfUserId selfId: UUID,
        reminders: [ReminderDTO],
        events: [ReminderEventDTO] = [],
        requestAuthIfNeeded: Bool = true
    ) async {
        if requestAuthIfNeeded {
            await requestAuthorizationIfNeeded()
        }

        let center = UNUserNotificationCenter.current()
        // Preserve milestone.* notifications so the milestones scheduler can
        // own them independently of reminder churn.
        let pending = await center.pendingNotificationRequests()
        let toRemove = pending
            .map(\.identifier)
            .filter { !$0.hasPrefix("milestone.") }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)

        for reminder in reminders where reminder.targetId == selfId {
            let completed = reminder.isCompleted(in: events)
            // A handled one-shot is done forever — never ping it again.
            if completed && !reminder.repeatsOnSchedule { continue }
            await schedule(reminder, completedThisPeriod: completed)
        }
    }

    /// Wipes every pending request (reminders + milestones). For sign-out and
    /// account deletion, so the previous account's reminders stop firing.
    func clearAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
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

    private func schedule(_ reminder: ReminderDTO, completedThisPeriod: Bool = false) async {
        if case .randomRecurring = reminder.trigger {
            await scheduleRandomRecurring(reminder, skipToday: completedThisPeriod)
            return
        }
        guard let trigger = makeTrigger(for: reminder) else { return }
        await add(reminder, trigger: trigger, identifier: reminder.id.uuidString)
    }

    /// iOS has no "repeat daily at a random time" trigger, so we lay down the
    /// next few days as individual one-time notifications, each at its own
    /// random moment inside the window. Every reschedule (app open, save,
    /// completion) re-extends the runway.
    private static let randomRecurringRunwayDays = 5

    private func scheduleRandomRecurring(_ reminder: ReminderDTO, skipToday: Bool = false) async {
        guard case .randomRecurring(let start, let end) = reminder.trigger else { return }
        let cal = Calendar.current
        let now = Date.now
        let startComps = cal.dateComponents([.hour, .minute], from: start)
        let endComps = cal.dateComponents([.hour, .minute], from: end)

        for dayOffset in 0..<Self.randomRecurringRunwayDays {
            if dayOffset == 0 && skipToday { continue }
            guard
                let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now)),
                let windowStart = cal.date(
                    bySettingHour: startComps.hour ?? 0, minute: startComps.minute ?? 0,
                    second: 0, of: day),
                let windowEnd = cal.date(
                    bySettingHour: endComps.hour ?? 0, minute: endComps.minute ?? 0,
                    second: 0, of: day),
                windowEnd > windowStart
            else { continue }

            var fireAt = Self.stablePick(in: windowStart...windowEnd, reminderId: reminder.id, day: day)
            if fireAt <= now {
                // Today's stable pick already passed. Re-picking later in the
                // window would ping again on every reschedule (each app open
                // re-runs this — including the open caused by tapping today's
                // notification). Only a reminder created today *after* its
                // pick — which therefore never got scheduled — falls forward
                // into what's left of the window; everyone else skips today.
                let created = reminder.createdAt ?? .distantPast
                guard windowEnd > now,
                      created > fireAt,
                      cal.isDate(created, inSameDayAs: now)
                else { continue }
                fireAt = Date(
                    timeIntervalSince1970: .random(
                        in: now.timeIntervalSince1970...windowEnd.timeIntervalSince1970
                    )
                )
            }

            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            await add(reminder, trigger: trigger, identifier: "\(reminder.id.uuidString).day\(dayOffset)")
        }
    }

    /// Deterministic "random" moment inside the window for a given reminder +
    /// day. Stable across reschedules so reopening the app mid-window can't
    /// silently move today's pick into the past and drop the notification.
    static func stablePick(in window: ClosedRange<Date>, reminderId: UUID, day: Date) -> Date {
        // FNV-1a over the uuid + day ordinal — UUID.hashValue is salted per
        // process, so it can't be the seed.
        var hash: UInt64 = 0xcbf29ce484222325
        let dayOrdinal = Int(day.timeIntervalSince1970 / 86_400)
        for byte in Array(reminderId.uuidString.utf8) + Array("\(dayOrdinal)".utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        let unit = Double(hash % 1_000_000) / 1_000_000.0
        let interval = window.upperBound.timeIntervalSince(window.lowerBound)
        return window.lowerBound.addingTimeInterval(interval * unit)
    }

    private func add(
        _ reminder: ReminderDTO, trigger: UNNotificationTrigger, identifier: String
    ) async {
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
            identifier: identifier,
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

        case .randomRecurring:
            // Handled by scheduleRandomRecurring — never reaches here.
            return nil

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
