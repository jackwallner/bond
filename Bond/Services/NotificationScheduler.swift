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
    ///   dialog appears - otherwise the primer's `.notDetermined` guard never
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

        let serverDelivers = PushRegistrar.shared.serverDelivers(for: selfId)
        for reminder in reminders
        where Self.armsLocally(reminder, me: selfId, serverDelivers: serverDelivers) {
            let completed = reminder.isCompleted(in: events)
            // A handled one-shot is done forever - never ping it again.
            if completed && !reminder.repeatsOnSchedule { continue }
            await schedule(reminder, completedThisPeriod: completed)
        }
    }

    /// Which reminders this phone arms itself. Nothing for the partner. Once the
    /// server delivers here, it owns the time of what the partner wrote, so a
    /// local copy would ping twice; only a place stays here, because only the
    /// phone knows where it is.
    nonisolated static func armsLocally(_ reminder: ReminderDTO, me: UUID, serverDelivers: Bool) -> Bool {
        guard reminder.targetId == me else { return false }
        guard serverDelivers, reminder.authorId != me else { return true }
        return reminder.triggerType == "location"
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
    func rescheduleMilestones(_ milestones: [MilestoneDTO], requestAuthIfNeeded: Bool = true) async {
        if requestAuthIfNeeded {
            await requestAuthorizationIfNeeded()
        }

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

        let title = milestone.label?.isEmpty == false
            ? milestone.label!
            : MilestoneDTO.kindTitle(milestone.kind)

        let offsets: [(days: Int, body: String)] = [
            (-7, String(localized: "\(title) is in 1 week.")),
            (-1, String(localized: "\(title) is tomorrow.")),
            (0,  String(localized: "\(title) is today."))
        ]

        for (days, body) in offsets {
            guard let fireDate = calendar.date(byAdding: .day, value: days, to: fireOn),
                  fireDate > .now
            else { continue }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
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
        for request in Self.plan(for: reminder, completedThisPeriod: completedThisPeriod) {
            await add(reminder, trigger: request.trigger, identifier: request.identifier)
        }
    }

    /// One pending request the scheduler lays down for a reminder.
    struct PlannedNotification {
        let identifier: String
        let trigger: UNNotificationTrigger
    }

    /// The requests that deliver one reminder from `now` on. Pure, so tests can
    /// read each trigger's `nextTriggerDate()` without notification permission.
    nonisolated static func plan(
        for reminder: ReminderDTO,
        completedThisPeriod: Bool = false,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [PlannedNotification] {
        let id = reminder.id.uuidString
        switch reminder.trigger {
        case .oneTime(let fireAt):
            return [oneShot(id, at: fireAt, now: now)].compactMap { $0 }

        case .randomWindow:
            // fireAt was already randomized at save time.
            guard let fireAt = reminder.fireAt else { return [] }
            return [oneShot(id, at: fireAt, now: now)].compactMap { $0 }

        case .recurring(let rrule, let anchor):
            guard let preset = RecurrencePreset(rrule: rrule) else { return [] }
            return recurringPlan(id: id, preset: preset, anchor: anchor, now: now, calendar: calendar)

        case .randomRecurring(let start, let end):
            return dailyRandomPlan(
                reminder, start: start, end: end, skipToday: completedThisPeriod, now: now, calendar: calendar
            )

        case .location(let geofence, let onEntry):
            let center = CLLocationCoordinate2D(
                latitude: geofence.latitude, longitude: geofence.longitude
            )
            let region = CLCircularRegion(
                center: center,
                radius: geofence.radiusMeters,
                identifier: "bond.\(id)"
            )
            region.notifyOnEntry = onEntry
            region.notifyOnExit = !onEntry
            return [PlannedNotification(
                identifier: id, trigger: UNLocationNotificationTrigger(region: region, repeats: false)
            )]

        case .none:
            return []
        }
    }

    /// A single delivery at an instant. A time interval, not calendar
    /// components: components float with the device's zone, so after a flight
    /// the reminder rang hours off the time the list shows.
    nonisolated private static func oneShot(_ identifier: String, at date: Date, now: Date) -> PlannedNotification? {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return nil }
        return PlannedNotification(
            identifier: identifier,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
    }

    /// How many occurrences of a reminder that starts later are laid down one
    /// by one. The first rebuild after the start swaps them for the repeating
    /// trigger.
    nonisolated private static func startRunway(_ preset: RecurrencePreset) -> Int {
        switch preset {
        case .daily:   7
        case .weekly:  4
        case .monthly: 3
        case .yearly:  2
        }
    }

    nonisolated private static func recurringPlan(
        id: String, preset: RecurrencePreset, anchor: Date, now: Date, calendar: Calendar
    ) -> [PlannedNotification] {
        let comps = recurrenceComponents(for: preset, anchor: anchor, calendar: calendar)
        let first = preset.firstIndex(after: now, anchor: anchor, calendar: calendar)
        let next = preset.occurrence(first, from: anchor, calendar: calendar)

        // A repeating trigger has no start date: it fires at the next match from
        // now. When "Starting" is further out than that, lay the first
        // occurrences down one by one instead.
        if anchor > now,
           let match = calendar.nextDate(after: now, matching: comps, matchingPolicy: .strict),
           next.timeIntervalSince(match) >= 60 {
            return (0..<startRunway(preset)).compactMap { n in
                oneShot("\(id).start\(n)", at: preset.occurrence(n, from: anchor, calendar: calendar), now: now)
            }
        }

        var plan = [PlannedNotification(
            identifier: id, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        )]
        // The repeating trigger skips the months without the anchor's day (the
        // 29th to the 31st) and the years without February 29. The list and the
        // server clamp to the last day instead, so those occurrences go down one
        // by one.
        let clampHorizon: Int
        switch preset {
        case .monthly where (comps.day ?? 0) > 28: clampHorizon = 12
        case .yearly where comps.month == 2 && comps.day == 29: clampHorizon = 4
        default: clampHorizon = 0
        }
        for n in first..<(first + clampHorizon) {
            let occurrence = preset.occurrence(n, from: anchor, calendar: calendar)
            guard calendar.component(.day, from: occurrence) != comps.day else { continue }
            if let request = oneShot("\(id).clamp\(n)", at: occurrence, now: now) {
                plan.append(request)
            }
        }
        return plan
    }

    /// iOS has no "repeat daily at a random time" trigger. Each weekday gets
    /// its own weekly repeating request at that day's random moment inside the
    /// window, so the reminder fires every day even if the app is never opened
    /// again (one-time requests ran out after five days). Every rebuild (app
    /// open, save, completion) picks new moments for the coming week.
    nonisolated private static func dailyRandomPlan(
        _ reminder: ReminderDTO, start: Date, end: Date, skipToday: Bool, now: Date, calendar cal: Calendar
    ) -> [PlannedNotification] {
        let id = reminder.id.uuidString
        let startComps = cal.dateComponents([.hour, .minute], from: start)
        let endComps = cal.dateComponents([.hour, .minute], from: end)
        func window(on day: Date) -> ClosedRange<Date>? {
            guard
                let windowStart = cal.date(
                    bySettingHour: startComps.hour ?? 0, minute: startComps.minute ?? 0, second: 0, of: day),
                let windowEnd = cal.date(
                    bySettingHour: endComps.hour ?? 0, minute: endComps.minute ?? 0, second: 0, of: day),
                windowEnd > windowStart
            else { return nil }
            return windowStart...windowEnd
        }
        func weekly(_ identifier: String, at date: Date) -> PlannedNotification {
            let comps = cal.dateComponents([.weekday, .hour, .minute], from: date)
            return PlannedNotification(
                identifier: identifier, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            )
        }

        var plan: [PlannedNotification] = []
        let today = cal.startOfDay(for: now)
        for dayOffset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: today),
                  let span = window(on: day)
            else { continue }
            let identifier = "\(id).day\(dayOffset)"
            let pick = stablePick(in: span, reminderId: reminder.id, day: day)

            guard dayOffset == 0 else {
                plan.append(weekly(identifier, at: pick))
                continue
            }
            if pick > now && skipToday {
                // Done today before today's moment: today's request must not
                // ring today. A moment already behind us next fires in a week.
                let latest = now.addingTimeInterval(-60)
                if latest > span.lowerBound {
                    let earlier = stablePick(in: span.lowerBound...latest, reminderId: reminder.id, day: day)
                    plan.append(weekly(identifier, at: earlier))
                } else if let nextWeek = cal.date(byAdding: .day, value: 7, to: day),
                          let nextSpan = window(on: nextWeek),
                          let request = oneShot(
                              identifier,
                              at: stablePick(in: nextSpan, reminderId: reminder.id, day: nextWeek),
                              now: now) {
                    plan.append(request)
                }
                continue
            }
            plan.append(weekly(identifier, at: pick))
            // Today's stable pick already passed. Picking again later in the
            // window would ping again on every rebuild (each app open re-runs
            // this, including the open caused by tapping today's notification).
            // Only a reminder created today after its pick, which therefore never
            // rang, falls forward into what is left of the window: from a minute
            // after it was made, at the same stable fraction. The server picks the
            // same moment (0019 reminder_next_push_at), so a handoff between the
            // two neither drops nor repeats it.
            let created = reminder.createdAt ?? .distantPast
            let lower = created.addingTimeInterval(60)
            guard pick <= now, !skipToday, created > pick, cal.isDate(created, inSameDayAs: now),
                  lower < span.upperBound
            else { continue }
            let fallForward = stablePick(in: lower...span.upperBound, reminderId: reminder.id, day: day)
            if let request = oneShot("\(id).today", at: fallForward, now: now) {
                plan.append(request)
            }
        }
        return plan
    }

    /// Deterministic "random" moment inside the window for a given reminder +
    /// day. Stable across reschedules so reopening the app mid-window can't
    /// silently move today's pick into the past and drop the notification.
    /// The server computes the same bytes (0019 daily_pick_unit), so both agree
    /// on the moment; change one only with the other.
    nonisolated static func stablePick(in window: ClosedRange<Date>, reminderId: UUID, day: Date) -> Date {
        // FNV-1a over the uuid + day ordinal - UUID.hashValue is salted per
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

    nonisolated private static func recurrenceComponents(
        for preset: RecurrencePreset, anchor: Date, calendar cal: Calendar
    ) -> DateComponents {
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
