#if DEBUG
import Foundation

/// Local-only paired data for literal product screenshots. The seed never
/// writes to Supabase and is unavailable to Release builds.
@MainActor
enum BondScreenshotSeed {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-BondScreenshotSeed")
    }

    private static let me = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private static let partner = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private static let couple = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    private static let question = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!

    static func apply(
        supabase: SupabaseService,
        store: PurchasesService,
        pairing: PairingService,
        reminders: ReminderRepository,
        milestones: MilestonesService,
        events: ReminderEventRepository,
        checkIn: DailyCheckInService
    ) {
        guard isEnabled else { return }

        let now = Date()
        supabase.currentUserId = me
        supabase.isAnonymous = true
        pairing.coupleId = couple
        pairing.partnerProfile = ProfileDTO(
            id: partner,
            displayName: "Sam",
            avatarUrl: nil,
            apnsToken: nil,
            loveLanguage: "time",
            createdAt: now
        )
        pairing.solo = false
        pairing.justPaired = false

        let preferences = OnboardingPreferences.shared
        preferences.partnerName = "Sam"
        preferences.partnerLoveLanguages = [.time, .words]
        preferences.focusAreas = [.gestures, .dates]
        preferences.committedAt = now

        store.setLocalOverride(isPremium: true)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        let dinner = calendar.date(byAdding: .day, value: 3, to: today)
            .flatMap { calendar.date(bySettingHour: 18, minute: 30, second: 0, of: $0) } ?? nextWeek
        // A month in, so a week of follow-through and the streaks have history.
        let joined = calendar.date(byAdding: .day, value: -30, to: today) ?? now

        func reminder(
            _ n: Int, by author: UUID, for target: UUID, _ title: String, note: String? = nil,
            _ language: LoveLanguage, rrule: String? = nil, fireAt: Date
        ) -> ReminderDTO {
            ReminderDTO(
                id: UUID(uuidString: "55555555-5555-4555-8555-55555555555\(n)")!,
                coupleId: couple,
                authorId: author,
                targetId: target,
                title: title,
                body: note,
                loveLanguage: language,
                triggerType: rrule == nil ? "one_time" : "recurring",
                fireAt: fireAt,
                rrule: rrule,
                geofence: nil,
                windowStart: nil,
                windowEnd: nil,
                status: "active",
                surpriseHiddenFromPartner: false,
                createdAt: joined
            )
        }

        let reminderRows = [
            reminder(1, by: me, for: partner, "Tell Sam one thing you appreciate",
                     note: "A small note goes a long way.", .words, rrule: "FREQ=DAILY", fireAt: tomorrow),
            reminder(2, by: me, for: partner, "Plan a ten-minute walk together",
                     .time, rrule: "FREQ=WEEKLY", fireAt: tomorrow),
            reminder(3, by: partner, for: me, "Bring home their favorite snack",
                     note: "The little details count.", .gifts, fireAt: nextWeek),
            reminder(4, by: me, for: partner, "Take the Sunday dishes off Sam's plate",
                     .acts, rrule: "FREQ=WEEKLY", fireAt: nextWeek),
            reminder(5, by: me, for: partner, "A long hug before work",
                     .touch, rrule: "FREQ=DAILY", fireAt: tomorrow),
            reminder(6, by: me, for: partner, "Book dinner at Lucia's",
                     note: "Sam's been wanting to try it.", .time, fireAt: dinner),
            reminder(7, by: me, for: partner, "Leave a note in Sam's bag",
                     .words, rrule: "FREQ=WEEKLY", fireAt: calendar.date(byAdding: .day, value: 4, to: now) ?? nextWeek),
        ]
        reminders.reminders = reminderRows
        reminders.onChange(reminderRows)

        milestones.milestones = [
            MilestoneDTO(
                id: UUID(uuidString: "66666666-6666-4666-8666-666666666661")!,
                coupleId: couple,
                kind: "anniversary",
                label: "Our anniversary",
                date: nextWeek,
                recur: true,
                createdAt: now
            ),
            MilestoneDTO(
                id: UUID(uuidString: "66666666-6666-4666-8666-666666666662")!,
                coupleId: couple,
                kind: "birthday",
                label: "Sam's birthday",
                date: Calendar.current.date(byAdding: .day, value: 21, to: now) ?? now,
                recur: true,
                createdAt: now
            ),
            MilestoneDTO(
                id: UUID(uuidString: "66666666-6666-4666-8666-666666666663")!,
                coupleId: couple,
                kind: "custom",
                label: "Weekend away",
                date: Calendar.current.date(byAdding: .day, value: 35, to: now) ?? now,
                recur: false,
                createdAt: now
            ),
        ]

        // Done days, counted back from today: notes every day but one this
        // month (a 12 day streak, 15 at best), hugs most days, the weekly
        // walk, dishes and bag note each week. Today's land a little before launch.
        let doneDays: [(reminder: Int, days: [Int])] = [
            (0, Array(0...11) + Array(13...27)),
            (4, [0, 1, 3, 4, 6, 8, 9, 11, 14, 15, 17, 20, 22]),
            (1, [2, 9, 16, 23]),
            (3, [1, 8, 15, 22]),
            (6, [5, 19, 26]),
        ]
        let earlierToday = max(today.addingTimeInterval(60), now.addingTimeInterval(-2 * 60 * 60))
        var eventRows: [ReminderEventDTO] = []
        for (index, days) in doneDays {
            for day in days {
                let at = day == 0
                    ? earlierToday
                    : calendar.date(byAdding: .day, value: -day, to: today)?.addingTimeInterval(19.5 * 60 * 60) ?? now
                eventRows.append(ReminderEventDTO(
                    id: UUID(),
                    reminderId: reminderRows[index].id,
                    coupleId: couple,
                    firedAt: at,
                    actedAt: at,
                    reaction: day % 3 == 0 ? "heart" : ""
                ))
            }
        }
        events.events = eventRows

        checkIn.todaysQuestion = DailyQuestionDTO(
            id: question,
            question: "What would make today feel a little more connected?",
            category: "connection",
            loveLanguage: .time
        )
        checkIn.myResponse = QuestionResponseDTO(
            id: UUID(uuidString: "88888888-8888-4888-8888-888888888881")!,
            questionId: question,
            coupleId: couple,
            userId: me,
            response: "A walk after dinner, just the two of us.",
            createdAt: now
        )
        checkIn.partnerResponse = QuestionResponseDTO(
            id: UUID(uuidString: "88888888-8888-4888-8888-888888888882")!,
            questionId: question,
            coupleId: couple,
            userId: partner,
            response: "A quiet coffee and a little time together.",
            createdAt: now
        )
    }
}
#endif
