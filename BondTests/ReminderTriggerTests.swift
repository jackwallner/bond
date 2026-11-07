import Foundation
import Testing
import UserNotifications

@testable import Bond

struct ReminderTriggerTests {
    // MARK: — kindRaw

    @Test func kindRaw_oneTime() {
        let t = ReminderTrigger.oneTime(fireAt: .now)
        #expect(t.kindRaw == "one_time")
    }

    @Test func kindRaw_recurring() {
        let t = ReminderTrigger.recurring(rrule: "FREQ=DAILY", nextFire: .now)
        #expect(t.kindRaw == "recurring")
    }

    @Test func kindRaw_location() {
        let g = Geofence(latitude: 0, longitude: 0, radiusMeters: 200, label: "Home")
        let t = ReminderTrigger.location(geofence: g, onEntry: true)
        #expect(t.kindRaw == "location")
    }

    @Test func kindRaw_randomWindow() {
        let t = ReminderTrigger.randomWindow(start: .now, end: .now.addingTimeInterval(3600))
        #expect(t.kindRaw == "random_window")
    }

    // MARK: — nextFireDate

    @Test func nextFireDate_oneTime() {
        let date = DateComponents(calendar: .current, year: 2026, month: 7, day: 4, hour: 12).date!
        let t = ReminderTrigger.oneTime(fireAt: date)
        #expect(t.nextFireDate == date)
    }

    @Test func nextFireDate_recurring() {
        let date = DateComponents(calendar: .current, year: 2026, month: 7, day: 4, hour: 12).date!
        let t = ReminderTrigger.recurring(rrule: "FREQ=WEEKLY", nextFire: date)
        #expect(t.nextFireDate == date)
    }

    @Test func nextFireDate_location() {
        let g = Geofence(latitude: 0, longitude: 0, radiusMeters: 200, label: "Home")
        let t = ReminderTrigger.location(geofence: g, onEntry: true)
        #expect(t.nextFireDate == nil)
    }

    @Test func nextFireDate_randomWindow() {
        let s = DateComponents(calendar: .current, year: 2026, month: 7, day: 4, hour: 9).date!
        let e = DateComponents(calendar: .current, year: 2026, month: 7, day: 4, hour: 17).date!
        let t = ReminderTrigger.randomWindow(start: s, end: e)
        #expect(t.nextFireDate == e)
    }

    // MARK: — upcomingFireDate (future-aware)

    @Test func upcomingFireDate_oneTime_returnsFireAt() {
        let date = DateComponents(calendar: .current, year: 2030, month: 1, day: 1, hour: 9).date!
        let t = ReminderTrigger.oneTime(fireAt: date)
        #expect(t.upcomingFireDate(after: .now) == date)
    }

    @Test func upcomingFireDate_recurring_pastAnchor_advancesToFuture() {
        let anchor = DateComponents(calendar: .current, year: 2020, month: 1, day: 1, hour: 9).date!
        let reference = DateComponents(calendar: .current, year: 2026, month: 5, day: 16, hour: 12).date!
        let t = ReminderTrigger.recurring(rrule: "FREQ=DAILY", nextFire: anchor)
        let next = t.upcomingFireDate(after: reference)
        #expect(next != nil)
        #expect(next! > reference)
    }

    @Test func upcomingFireDate_recurring_futureAnchor_staysPut() {
        let anchor = DateComponents(calendar: .current, year: 2030, month: 6, day: 1, hour: 9).date!
        let reference = DateComponents(calendar: .current, year: 2026, month: 5, day: 16).date!
        let t = ReminderTrigger.recurring(rrule: "FREQ=WEEKLY", nextFire: anchor)
        #expect(t.upcomingFireDate(after: reference) == anchor)
    }

    @Test func upcomingFireDate_location_returnsNil() {
        let g = Geofence(latitude: 0, longitude: 0, radiusMeters: 200, label: "Home")
        let t = ReminderTrigger.location(geofence: g, onEntry: true)
        #expect(t.upcomingFireDate(after: .now) == nil)
    }

    @Test func upcomingFireDate_randomWindow_returnsEnd() {
        let s = DateComponents(calendar: .current, year: 2026, month: 7, day: 4, hour: 9).date!
        let e = DateComponents(calendar: .current, year: 2026, month: 7, day: 4, hour: 17).date!
        let t = ReminderTrigger.randomWindow(start: s, end: e)
        #expect(t.upcomingFireDate(after: .now) == e)
    }

    // MARK: — Codable round-trip

    @Test func codable_oneTime() throws {
        let date = DateComponents(calendar: .current, year: 2026, month: 12, day: 25, hour: 8).date!
        let original = ReminderTrigger.oneTime(fireAt: date)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReminderTrigger.self, from: data)
        #expect(decoded == original)
        #expect(decoded.kindRaw == "one_time")
    }

    @Test func codable_recurring() throws {
        let date = DateComponents(calendar: .current, year: 2026, month: 1, day: 1, hour: 0).date!
        let original = ReminderTrigger.recurring(rrule: "FREQ=MONTHLY", nextFire: date)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReminderTrigger.self, from: data)
        #expect(decoded == original)
    }

    @Test func codable_location() throws {
        let g = Geofence(latitude: 37.7749, longitude: -122.4194, radiusMeters: 200, label: "Home")
        let original = ReminderTrigger.location(geofence: g, onEntry: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReminderTrigger.self, from: data)
        #expect(decoded == original)
    }

    @Test func codable_randomWindow() throws {
        let s = DateComponents(calendar: .current, year: 2026, month: 7, day: 4, hour: 9).date!
        let e = DateComponents(calendar: .current, year: 2026, month: 7, day: 4, hour: 17).date!
        let original = ReminderTrigger.randomWindow(start: s, end: e)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReminderTrigger.self, from: data)
        #expect(decoded == original)
    }
}

struct GeofenceTests {
    @Test func codable_roundTrip() throws {
        let original = Geofence(latitude: 37.7749, longitude: -122.4194, radiusMeters: 200, label: "Home")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Geofence.self, from: data)
        #expect(decoded.latitude == 37.7749)
        #expect(decoded.longitude == -122.4194)
        #expect(decoded.radiusMeters == 200)
        #expect(decoded.label == "Home")
    }
}

// MARK: - State machine audit 2026-11-06: the on-device schedule (B3, B6, B9, B10)

/// Each test reads `nextTriggerDate()` of the requests `NotificationScheduler.plan`
/// lays down, which needs no notification permission.
@MainActor
@Suite(.serialized)
struct SchedulePlanTests {
    private let me = UUID()

    private func reminder(
        _ type: String, fireAt: Date?, rrule: String? = nil,
        windowStart: Date? = nil, windowEnd: Date? = nil, createdAt: Date? = nil, target: UUID? = nil
    ) -> ReminderDTO {
        ReminderDTO(
            id: UUID(), coupleId: UUID(), authorId: me, targetId: target ?? me,
            title: "Test", body: nil, loveLanguage: .words, triggerType: type,
            fireAt: fireAt, rrule: rrule, geofence: nil, windowStart: windowStart, windowEnd: windowEnd,
            status: "scheduled", surpriseHiddenFromPartner: false, createdAt: createdAt
        )
    }

    private func nextFire(_ trigger: UNNotificationTrigger) -> Date? {
        if let calendar = trigger as? UNCalendarNotificationTrigger { return calendar.nextTriggerDate() }
        if let interval = trigger as? UNTimeIntervalNotificationTrigger { return interval.nextTriggerDate() }
        return nil
    }

    private func firstFire(_ reminder: ReminderDTO, calendar: Calendar = .current) -> Date? {
        NotificationScheduler.plan(for: reminder, calendar: calendar).compactMap { nextFire($0.trigger) }.min()
    }

    // B9: a recurring reminder's "Starting" date.

    @Test func b9_aDailyThatStartsIn40DaysDoesNotRingBeforeItsStart() throws {
        let anchor = try #require(Calendar.current.date(byAdding: .day, value: 40, to: .now))
        let daily = reminder("recurring", fireAt: anchor, rrule: "FREQ=DAILY")
        let first = try #require(firstFire(daily))
        #expect(abs(first.timeIntervalSince(anchor)) < 5, "first ring \(first), start \(anchor)")
    }

    @Test func b9_aWeeklyThatStartsIn3WeeksDoesNotRingBeforeItsStart() throws {
        let anchor = try #require(Calendar.current.date(byAdding: .day, value: 21, to: .now))
        let weekly = reminder("recurring", fireAt: anchor, rrule: "FREQ=WEEKLY")
        let first = try #require(firstFire(weekly))
        #expect(abs(first.timeIntervalSince(anchor)) < 5)
    }

    @Test func b9_control_aDailyThatAlreadyStartedRepeatsWithinADay() throws {
        let anchor = try #require(Calendar.current.date(byAdding: .day, value: -10, to: .now))
        let daily = reminder("recurring", fireAt: anchor, rrule: "FREQ=DAILY")
        let plan = NotificationScheduler.plan(for: daily)
        #expect(plan.count == 1)
        #expect((plan.first?.trigger as? UNCalendarNotificationTrigger)?.repeats == true)
        let first = try #require(firstFire(daily))
        #expect(first.timeIntervalSinceNow <= 86_400)
    }

    @Test func b9_aMonthlyReminderOnThe31stRingsInEveryMonth() throws {
        let cal = Calendar.current
        let year = cal.component(.year, from: .now) - 1
        let anchor = try #require(DateComponents(calendar: cal, year: year, month: 1, day: 31, hour: 9).date)
        let monthly = reminder("recurring", fireAt: anchor, rrule: "FREQ=MONTHLY")
        let plan = NotificationScheduler.plan(for: monthly)
        let repeating = plan.compactMap { $0.trigger as? UNCalendarNotificationTrigger }.filter(\.repeats)
        let oneShots = plan.filter { !($0.trigger is UNCalendarNotificationTrigger) }.compactMap { nextFire($0.trigger) }
        let first = RecurrencePreset.monthly.firstIndex(after: .now, anchor: anchor)
        for n in first..<(first + 12) {
            let occurrence = RecurrencePreset.monthly.occurrence(n, from: anchor)
            let day = cal.component(.day, from: occurrence)
            let byRepeating = repeating.contains { $0.dateComponents.day == day && $0.dateComponents.hour == 9 }
            let byOneShot = oneShots.contains { abs($0.timeIntervalSince(occurrence)) < 5 }
            #expect(byRepeating || byOneShot, "nothing rings on \(occurrence)")
        }
    }

    @Test func b9_theListShowsTheClampedDayAndThenThe31stAgain() throws {
        let cal = Calendar.current
        let anchor = try #require(DateComponents(calendar: cal, year: 2026, month: 1, day: 31, hour: 9).date)
        let reference = try #require(DateComponents(calendar: cal, year: 2026, month: 3, day: 1).date)
        let trigger = ReminderTrigger.recurring(rrule: "FREQ=MONTHLY", nextFire: anchor)
        let expected = try #require(DateComponents(calendar: cal, year: 2026, month: 3, day: 31, hour: 9).date)
        #expect(trigger.upcomingFireDate(after: reference) == expected)
    }

    // B10: a pending one-shot after a time zone change.

    @Test func b10_aOneTimeReminderRingsAtItsInstantAfterAZoneChange() throws {
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        NSTimeZone.default = losAngeles
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = losAngeles
        let fireAt = Date.now.addingTimeInterval(3 * 3_600)
        let oneTime = reminder("one_time", fireAt: fireAt)
        let surprise = reminder("random_window", fireAt: fireAt, windowStart: .now, windowEnd: fireAt)
        let plans = [oneTime, surprise].map { NotificationScheduler.plan(for: $0, calendar: cal) }

        NSTimeZone.default = try #require(TimeZone(identifier: "America/New_York"))

        for plan in plans {
            let next = try #require(plan.first.flatMap { nextFire($0.trigger) })
            #expect(abs(next.timeIntervalSince(fireAt)) < 60, "rings at \(next), saved for \(fireAt)")
        }
    }

    // B6: a daily random reminder when the app is not opened again.

    private func dailyRandom() throws -> ReminderDTO {
        let cal = Calendar.current
        let start = try #require(cal.date(bySettingHour: 18, minute: 0, second: 0, of: .now))
        let end = try #require(cal.date(bySettingHour: 21, minute: 0, second: 0, of: .now))
        return reminder(
            "random_window", fireAt: end, rrule: "FREQ=DAILY", windowStart: start, windowEnd: end,
            createdAt: .now.addingTimeInterval(-30 * 86_400)
        )
    }

    @Test func b6_aDailyRandomReminderRingsEveryDayWithoutTheAppBeingOpened() throws {
        let plan = NotificationScheduler.plan(for: try dailyRandom())
        let repeating = plan.compactMap { $0.trigger as? UNCalendarNotificationTrigger }.filter(\.repeats)
        #expect(Set(repeating.compactMap(\.dateComponents.weekday)) == Set(1...7), "stops after the last one-time request")
        for trigger in repeating {
            let minute = (trigger.dateComponents.hour ?? 0) * 60 + (trigger.dateComponents.minute ?? 0)
            #expect((18 * 60)...(21 * 60) ~= minute)
        }
    }

    @Test func b6_doneTodayItSkipsTodayAndStillCoversEveryWeekday() throws {
        let cal = Calendar.current
        let plan = NotificationScheduler.plan(for: try dailyRandom(), completedThisPeriod: true)
        let fires = plan.compactMap { nextFire($0.trigger) }
        #expect(!fires.contains { cal.isDateInToday($0) }, "rings again today")
        var weekdays = Set(plan.compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents.weekday })
        for request in plan where !(request.trigger is UNCalendarNotificationTrigger) {
            if let date = nextFire(request.trigger) { weekdays.insert(cal.component(.weekday, from: date)) }
        }
        #expect(weekdays == Set(1...7))
    }

    // B3: template packs arrive one at a time.

    @Test func b3_dailyPacksImportedTogetherNeverRingAtTheSameTime() {
        let target = UUID()
        var imported: [ReminderDTO] = []
        for group in [ReminderTemplateGroup.dailyAffirmations, .newParents, .appreciation] {
            let dates = TemplateSchedule.fireDates(for: group.reminders, target: target, existing: imported)
            #expect(dates.count == group.reminders.count)
            imported += zip(group.reminders, dates).map { template, date in
                reminder(
                    template.triggerRecurrence == nil ? "one_time" : "recurring",
                    fireAt: date, rrule: template.triggerRecurrence?.rrule, target: target
                )
            }
        }
        let clock = imported.map { reminder -> Int in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: reminder.fireAt ?? .now)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        #expect(Set(clock).count == clock.count, "shared clock times: \(clock.sorted())")
        #expect(imported.allSatisfy { ($0.fireAt ?? .distantPast) > .now })
    }

    @Test func b3_aPackAvoidsTheTimesOfRemindersAlreadyThere() throws {
        let target = UUID()
        let nine = try #require(Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now))
        let existing = [reminder("recurring", fireAt: nine, rrule: "FREQ=DAILY", target: target)]
        let dates = TemplateSchedule.fireDates(
            for: ReminderTemplateGroup.newParents.reminders, target: target, existing: existing
        )
        #expect(!dates.contains { Calendar.current.component(.hour, from: $0) == 9 && Calendar.current.component(.minute, from: $0) == 0 })
    }
}
