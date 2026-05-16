import Foundation
import Testing

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
