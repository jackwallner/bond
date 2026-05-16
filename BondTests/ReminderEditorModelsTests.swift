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
