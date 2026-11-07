import Foundation
import Testing

@testable import Bond

struct ReminderTargetTests {
    @Test func titles() {
        #expect(ReminderTarget.me.title == "Me")
        #expect(ReminderTarget.partner.title == "Partner")
    }

    @Test func allCases() {
        #expect(ReminderTarget.allCases.count == 2)
    }
}

struct TriggerKindTests {
    @Test func titles() {
        #expect(TriggerKind.oneTime.title == "One time")
        #expect(TriggerKind.recurring.title == "Recurring")
        #expect(TriggerKind.location.title == "At a place")
        #expect(TriggerKind.randomWindow.title == "Random surprise")
    }

    @Test func isPremium() {
        #expect(TriggerKind.oneTime.isPremium == false)
        #expect(TriggerKind.recurring.isPremium == false)
        #expect(TriggerKind.location.isPremium == true)
        #expect(TriggerKind.randomWindow.isPremium == true)
    }

    @Test func allCases() {
        #expect(TriggerKind.allCases.count == 4)
    }
}

// MARK: - State machine audit 2026-11-06: B5, a banner tapped while the editor is open

@MainActor
struct NotificationOpenTests {
    private func reminder(_ title: String) -> ReminderDTO {
        let me = UUID()
        return ReminderDTO(
            id: UUID(), coupleId: UUID(), authorId: me, targetId: me,
            title: title, body: nil, loveLanguage: .words, triggerType: "one_time",
            fireAt: .now.addingTimeInterval(3_600), rrule: nil, geofence: nil, windowStart: nil, windowEnd: nil,
            status: "scheduled", surpriseHiddenFromPartner: false, createdAt: nil
        )
    }

    @Test func b5_aBannerTappedWhileEditingDoesNotSwapTheReminderUnderTheForm() {
        let a = reminder("A"), b = reminder("B")
        // Editing A; B's banner is tapped. Opening B now would leave A's form on
        // screen and Save would write it over B.
        #expect(ReminderListView.reminderToOpen(b.id, in: [a, b], whilePresenting: true) == nil)
        // Once the editor closes, the pending tap opens B.
        #expect(ReminderListView.reminderToOpen(b.id, in: [a, b], whilePresenting: false) == b)
    }

    @Test func b5_control_aTapForAReminderNotLoadedYetStaysPending() {
        #expect(ReminderListView.reminderToOpen(UUID(), in: [reminder("A")], whilePresenting: false) == nil)
        #expect(ReminderListView.reminderToOpen(nil, in: [reminder("A")], whilePresenting: false) == nil)
    }
}
