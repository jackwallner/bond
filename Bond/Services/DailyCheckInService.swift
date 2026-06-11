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
        guard let coupleId = pairing.coupleId else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let count: Int = try await supabase.client
                .from("daily_questions")
                .select("id", head: true, count: .exact)
                .execute()
                .count ?? 30

            let calendar = Calendar.current
            let dayOffset = calendar.ordinality(of: .day, in: .era, for: Date()) ?? 0
            // Stable seed: UUID bytes summed as Int. `String.hashValue` is salted
            // per-process, so partners would see different questions and a single
            // user would see a different question on every cold start.
            let coupleSeed = Self.stableSeed(from: coupleId)
            let questionIndex = abs((dayOffset &+ coupleSeed) % max(count, 1))

            // Explicit ORDER BY: without it Postgres row order is unspecified,
            // so the same index could resolve to different questions for the
            // two partners — or change for one user mid-day.
            let questions: [DailyQuestionDTO] = try await supabase.client
                .from("daily_questions")
                .select()
                .order("id", ascending: true)
                .range(from: questionIndex, to: questionIndex)
                .execute()
                .value

            guard let question = questions.first else {
                log.error("No questions found in DB — using fallback")
                todaysQuestion = DailyQuestionDTO(
                    id: UUID(),
                    question: "What is one thing you appreciated about your partner today?",
                    category: "appreciation",
                    loveLanguage: .words
                )
                return
            }

            todaysQuestion = question
            log.info("Loaded today's question: \(question.id)")
            await loadResponses(for: question.id, coupleId: coupleId)
        } catch {
            lastError = error.localizedDescription
            log.error("Failed to load question: \(error.localizedDescription)")
        }
    }

    private func loadResponses(for questionId: UUID, coupleId: UUID) async {
        guard let me = supabase.currentUserId else { return }

        do {
            let responses: [QuestionResponseDTO] = try await supabase.client
                .from("question_responses")
                .select()
                .eq("question_id", value: questionId.uuidString)
                .eq("couple_id", value: coupleId.uuidString)
                .execute()
                .value

            myResponse = responses.first { $0.userId == me }
            partnerResponse = responses.first { $0.userId != me }
        } catch {
            log.error("Failed to load responses: \(error.localizedDescription)")
        }
    }

    func submitResponse(_ text: String) async {
        guard let me = supabase.currentUserId,
              let coupleId = pairing.coupleId,
              let question = todaysQuestion
        else {
            lastError = "Not set up yet."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let payload: [String: AnyJSON] = [
                "question_id": .string(question.id.uuidString),
                "couple_id": .string(coupleId.uuidString),
                "user_id": .string(me.uuidString),
                "response": .string(text)
            ]
            try await supabase.client
                .from("question_responses")
                .upsert(payload, ignoreDuplicates: false)
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

    /// Deterministic integer derived from a UUID — stable across processes.
    private static func stableSeed(from uuid: UUID) -> Int {
        withUnsafeBytes(of: uuid.uuid) { bytes in
            bytes.reduce(0) { ($0 &* 31) &+ Int($1) }
        }
    }
}
