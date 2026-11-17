import Foundation
import OSLog
import Supabase

@MainActor
@Observable
final class DailyCheckInService {
    private let supabase = SupabaseService.shared
    private let pairing: PairingService
    private let log = Logger(subsystem: "com.jackwallner.bond", category: "checkin")

    var todaysQuestion: DailyQuestionDTO?
    var myResponse: QuestionResponseDTO?
    var partnerResponse: QuestionResponseDTO?
    var isLoading = false
    var lastError: String?

    init(pairing: PairingService) {
        self.pairing = pairing
    }

    func loadTodaysQuestion() async {
        #if DEBUG
        if BondScreenshotSeed.isEnabled { return }
        #endif
        guard let coupleId = pairing.coupleId else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let count: Int = try await supabase.client
                .from("daily_questions")
                .select("id", head: true, count: .exact)
                .execute()
                .count ?? 30

            let now = Date()
            let questionIndex = Self.questionIndex(
                day: Self.dayNumber(for: now), seed: Self.stableSeed(from: coupleId), count: count
            )

            // Explicit ORDER BY: without it Postgres row order is unspecified,
            // so the same index could resolve to different questions for the
            // two partners - or change for one user mid-day.
            let questions: [DailyQuestionDTO] = try await supabase.client
                .from("daily_questions")
                .select()
                .order("id", ascending: true)
                .range(from: questionIndex, to: questionIndex)
                .execute()
                .value

            guard let dayQuestion = questions.first else {
                log.error("No questions found in DB - using fallback")
                todaysQuestion = DailyQuestionDTO(
                    id: UUID(),
                    question: String(localized: "What is one thing you appreciated about your partner today?"),
                    category: "appreciation",
                    loveLanguage: .words
                )
                return
            }

            guard let me = supabase.currentUserId else { return }
            let recent = try await recentResponses(coupleId: coupleId, now: now)
            let currentId = Self.currentQuestionId(dayQuestion: dayQuestion.id, responses: recent, me: me, now: now)
            let question: DailyQuestionDTO
            if currentId == dayQuestion.id {
                question = dayQuestion
            } else {
                question = try await supabase.client
                    .from("daily_questions")
                    .select()
                    .eq("id", value: currentId.uuidString)
                    .single()
                    .execute()
                    .value
            }

            todaysQuestion = question
            log.info("Loaded today's question: \(question.id)")
            apply(recent, for: question.id, me: me)
        } catch {
            lastError = error.localizedDescription
            log.error("Failed to load question: \(error.localizedDescription)")
        }
    }

    /// How far back an answer can still be the couple's open question.
    nonisolated static let openWindow: TimeInterval = 24 * 3_600

    /// The couple's answers from the last two days: an open question was
    /// answered within a day, and the second answer to it within the next.
    /// Older ones belong to an earlier round of the same question.
    private func recentResponses(coupleId: UUID, now: Date) async throws -> [QuestionResponseDTO] {
        let since = now.addingTimeInterval(-2 * Self.openWindow)
        return try await supabase.client
            .from("question_responses")
            .select()
            .eq("couple_id", value: coupleId.uuidString)
            .gte("created_at", value: ISO8601DateFormatter().string(from: since))
            .execute()
            .value
    }

    private func apply(_ responses: [QuestionResponseDTO], for questionId: UUID, me: UUID) {
        let answers = responses.filter { $0.questionId == questionId }
        myResponse = answers.first { $0.userId == me }
        partnerResponse = answers.first { $0.userId != me }
    }

    /// The day a question belongs to: the local calendar date, numbered the
    /// way the store version numbers its UTC date, so the two agree for every
    /// hour the dates are the same. Counting days with Foundation's ordinality
    /// changed the question at 00:00 UTC in every zone (4 PM in Los Angeles).
    nonisolated static func dayNumber(for date: Date, in zone: TimeZone = .current) -> Int {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = zone
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? zone
        let parts = local.dateComponents([.year, .month, .day], from: date)
        guard let midnight = utc.date(from: parts) else { return 0 }
        return utc.ordinality(of: .day, in: .era, for: midnight) ?? 0
    }

    nonisolated static func questionIndex(day: Int, seed: Int, count: Int) -> Int {
        abs((day &+ seed) % max(count, 1))
    }

    /// Which question the couple is on, so both partners answer the same one
    /// and each sees the reveal, whatever their zones or app versions:
    /// 1. one the partner answered in the last day and this user has not,
    /// 2. else one both answered, completed today, to keep showing the reveal,
    /// 3. else one this user answered in the last day and the partner has not,
    /// 4. else the question of this user's local day.
    /// A question answered first is the couple's until the other answers it
    /// (for a day), so a midnight between the two answers, a partner in
    /// another zone, or a partner on a version that changes at 00:00 UTC no
    /// longer splits them onto different questions.
    nonisolated static func currentQuestionId(
        dayQuestion: UUID,
        responses: [QuestionResponseDTO],
        me: UUID,
        now: Date,
        calendar: Calendar = .current
    ) -> UUID {
        let openSince = now.addingTimeInterval(-openWindow)
        let byQuestion = Dictionary(grouping: responses, by: \.questionId)
        var waitingOnMe: [(UUID, Date)] = []
        var revealedToday: [(UUID, Date)] = []
        var waitingOnPartner: [(UUID, Date)] = []
        for (question, answers) in byQuestion {
            let mine = answers.first { $0.userId == me }
            let theirs = answers.first { $0.userId != me }
            switch (mine, theirs) {
            case (.none, .some(let theirs)) where theirs.createdAt > openSince:
                waitingOnMe.append((question, theirs.createdAt))
            case (.some(let mine), .some(let theirs)):
                let completed = max(mine.createdAt, theirs.createdAt)
                if calendar.isDate(completed, inSameDayAs: now) { revealedToday.append((question, completed)) }
            case (.some(let mine), .none) where mine.createdAt > openSince:
                waitingOnPartner.append((question, mine.createdAt))
            default:
                break
            }
        }
        for candidates in [waitingOnMe, revealedToday, waitingOnPartner] {
            if let newest = candidates.max(by: { $0.1 < $1.1 }) { return newest.0 }
        }
        return dayQuestion
    }

    private func loadResponses(for questionId: UUID, coupleId: UUID) async {
        guard let me = supabase.currentUserId else { return }
        do {
            apply(try await recentResponses(coupleId: coupleId, now: Date()), for: questionId, me: me)
        } catch {
            log.error("Failed to load responses: \(error.localizedDescription)")
        }
    }

    func submitResponse(_ text: String) async {
        guard let me = supabase.currentUserId,
              let coupleId = pairing.coupleId,
              let question = todaysQuestion
        else {
            lastError = String(localized: "Not set up yet.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let payload: [String: AnyJSON] = [
                "question_id": .string(question.id.uuidString),
                "couple_id": .string(coupleId.uuidString),
                "user_id": .string(me.uuidString),
                "response": .string(text),
                // A question comes round again after the bank is used up; the
                // new answer starts a new round, so its time moves with it.
                "created_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]
            try await supabase.client
                .from("question_responses")
                // The table is unique on these, not on the id the payload
                // leaves out: without the target a repeat round's answer was
                // a fresh insert that the earlier round's row rejected.
                .upsert(payload, onConflict: "question_id,couple_id,user_id", ignoreDuplicates: false)
                .execute()

            log.info("Submitted response for question \(question.id)")
            await loadResponses(for: question.id, coupleId: coupleId)
        } catch {
            lastError = error.localizedDescription
            log.error("Failed to submit response: \(error.localizedDescription)")
        }
    }

    func refresh() async {
        await loadTodaysQuestion()
    }

    var hasBothResponded: Bool {
        myResponse != nil && partnerResponse != nil
    }

    /// Deterministic integer derived from a UUID - stable across processes.
    nonisolated static func stableSeed(from uuid: UUID) -> Int {
        withUnsafeBytes(of: uuid.uuid) { bytes in
            bytes.reduce(0) { ($0 &* 31) &+ Int($1) }
        }
    }
}
