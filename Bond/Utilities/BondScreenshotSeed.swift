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

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let reminderRows = [
            ReminderDTO(
                id: UUID(uuidString: "55555555-5555-4555-8555-555555555551")!,
                coupleId: couple,
                authorId: me,
                targetId: partner,
                title: "Tell Sam one thing you appreciate",
                body: "A small note goes a long way.",
                loveLanguage: .words,
                triggerType: "recurring",
                fireAt: tomorrow,
                rrule: "FREQ=DAILY",
                geofence: nil,
                windowStart: nil,
                windowEnd: nil,
                status: "active",
                surpriseHiddenFromPartner: false,
                createdAt: now
            ),
            ReminderDTO(
                id: UUID(uuidString: "55555555-5555-4555-8555-555555555552")!,
                coupleId: couple,
                authorId: me,
                targetId: partner,
                title: "Plan a ten-minute walk together",
                body: nil,
                loveLanguage: .time,
                triggerType: "recurring",
                fireAt: tomorrow,
                rrule: "FREQ=WEEKLY",
                geofence: nil,
                windowStart: nil,
                windowEnd: nil,
                status: "active",
                surpriseHiddenFromPartner: false,
                createdAt: now
            ),
            ReminderDTO(
                id: UUID(uuidString: "55555555-5555-4555-8555-555555555553")!,
                coupleId: couple,
                authorId: partner,
                targetId: me,
                title: "Bring home their favorite snack",
                body: "The little details count.",
                loveLanguage: .gifts,
                triggerType: "one_time",
                fireAt: nextWeek,
                rrule: nil,
                geofence: nil,
                windowStart: nil,
                windowEnd: nil,
                status: "active",
                surpriseHiddenFromPartner: false,
                createdAt: now
            ),
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

        let completedReminder = reminderRows[0]
        events.events = [
            ReminderEventDTO(
                id: UUID(uuidString: "77777777-7777-4777-8777-777777777771")!,
                reminderId: completedReminder.id,
                coupleId: couple,
                firedAt: now,
                actedAt: now,
                reaction: "heart"
            ),
            ReminderEventDTO(
                id: UUID(uuidString: "77777777-7777-4777-8777-777777777772")!,
                reminderId: reminderRows[1].id,
                coupleId: couple,
                firedAt: Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now,
                actedAt: Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now,
                reaction: ""
            ),
        ]

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
