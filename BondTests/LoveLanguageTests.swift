import Foundation
import Testing

@testable import Bond

struct LoveLanguageTests {
    @Test func allCases_count() {
        #expect(LoveLanguage.allCases.count == 5)
    }

    @Test func titles_matchExpected() {
        #expect(LoveLanguage.words.title == "Words of Affirmation")
        #expect(LoveLanguage.acts.title == "Acts of Service")
        #expect(LoveLanguage.gifts.title == "Receiving Gifts")
        #expect(LoveLanguage.time.title == "Quality Time")
        #expect(LoveLanguage.touch.title == "Physical Touch")
    }

    @Test func symbolNames_areNonEmpty() {
        for lang in LoveLanguage.allCases {
            #expect(!lang.symbolName.isEmpty)
        }
    }

    @Test func allCases_distinctRawValues() {
        let rawValues = LoveLanguage.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }
}

// MARK: - State machine audit 2026-11-06: B4 (sm1), Insights show only what this user may see

@MainActor
struct InsightsVisibilityTests {
    private let me = UUID()
    private let partner = UUID()

    private func recurring(_ title: String, author: UUID, target: UUID, fireAt: Date) -> ReminderDTO {
        ReminderDTO(
            id: UUID(), coupleId: UUID(), authorId: author, targetId: target,
            title: title, body: nil, loveLanguage: .words, triggerType: "recurring",
            fireAt: fireAt, rrule: "FREQ=DAILY", geofence: nil, windowStart: nil, windowEnd: nil,
            status: "scheduled", surpriseHiddenFromPartner: false,
            createdAt: .now.addingTimeInterval(-10 * 86_400)
        )
    }

    private func done(_ reminder: ReminderDTO) -> ReminderEventDTO {
        ReminderEventDTO(
            id: UUID(), reminderId: reminder.id, coupleId: reminder.coupleId,
            firedAt: .now, actedAt: .now, reaction: nil
        )
    }

    @Test func b4_insightsOnlyCountAndNameWhatTheUserCanSee() {
        let mine = recurring("Mine", author: me, target: me, fireAt: .now.addingTimeInterval(5 * 86_400))
        let forMe = recurring("For me", author: partner, target: me, fireAt: .now.addingTimeInterval(4 * 86_400))
        let theirs = recurring("Partner private", author: partner, target: partner, fireAt: .now.addingTimeInterval(86_400))
        // The widget drops the partner's own reminder (it fires sooner, so it would win if kept).
        let widget = WidgetSnapshot.make(reminders: [mine, theirs], milestones: [], userId: me)
        #expect(widget.nextReminder?.title == "Mine")

        // What StatsView.analyzer builds from the couple's rows.
        let analyzer = LoveLanguageAnalyzer(
            visibleTo: me, reminders: [mine, forMe, theirs], events: [done(mine), done(theirs)]
        )

        #expect(analyzer.reminderCounts().map(\.1).reduce(0, +) == 2, "Total reminders counts the partner's private one")
        #expect(Set(analyzer.followThrough().map(\.reminder.title)) == ["Mine", "For me"], "Follow-through names the partner's private reminder")
        #expect(analyzer.eventCount == 1)
        #expect(analyzer.actedEventCount == 1)
        #expect(analyzer.partnerReminderCount == 1)
    }

    @Test func b4_signedOutSeesNothing() {
        let mine = recurring("Mine", author: me, target: me, fireAt: .now.addingTimeInterval(86_400))
        #expect(LoveLanguageAnalyzer(visibleTo: nil, reminders: [mine], events: []).reminderCount == 0)
    }
}
