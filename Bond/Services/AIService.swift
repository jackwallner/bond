import Foundation
import Supabase

struct AISuggestion: Codable, Sendable, Identifiable, Hashable {
    let title: String
    let loveLanguage: LoveLanguage
    let rationale: String

    var id: String { "\(loveLanguage.rawValue)\(title)" }

    enum CodingKeys: String, CodingKey {
        case title
        case loveLanguage = "love_language"
        case rationale
    }
}

@MainActor
@Observable
final class AIService {
    enum AIError: Error, LocalizedError {
        case dailyLimit
        case server(String)

        var errorDescription: String? {
            switch self {
            case .dailyLimit:        "You've hit today's AI limit. Try again tomorrow."
            case .server(let msg):   msg
            }
        }
    }

    private let supabase = SupabaseService.shared

    func rewrite(note: String, language: LoveLanguage) async throws -> String {
        struct Body: Encodable {
            let action = "rewrite"
            let language: String
            let note: String
        }
        struct Response: Decodable {
            let ok: Bool
            let text: String?
            let error: String?
        }
        let resp: Response = try await invoke(
            body: Body(language: language.rawValue, note: note)
        )
        guard resp.ok, let text = resp.text else {
            if resp.error?.contains("limit") == true { throw AIError.dailyLimit }
            throw AIError.server(resp.error ?? "unknown error")
        }
        return text
    }

    func suggest(coupleId: UUID) async throws -> [AISuggestion] {
        struct Body: Encodable {
            let action = "suggest"
            let coupleId: String
        }
        struct Response: Decodable {
            let ok: Bool
            let suggestions: [AISuggestion]?
            let error: String?
        }
        let resp: Response = try await invoke(
            body: Body(coupleId: coupleId.uuidString)
        )
        guard resp.ok, let suggestions = resp.suggestions else {
            if resp.error?.contains("limit") == true { throw AIError.dailyLimit }
            throw AIError.server(resp.error ?? "unknown error")
        }
        return suggestions
    }

    func digest(coupleId: UUID) async throws -> String {
        struct Body: Encodable {
            let action = "digest"
            let coupleId: String
        }
        struct Response: Decodable {
            let ok: Bool
            let digest: String?
            let error: String?
        }
        let resp: Response = try await invoke(
            body: Body(coupleId: coupleId.uuidString)
        )
        guard resp.ok, let digest = resp.digest else {
            if resp.error?.contains("limit") == true { throw AIError.dailyLimit }
            throw AIError.server(resp.error ?? "unknown error")
        }
        return digest
    }

    private func invoke<B: Encodable, R: Decodable>(body: B) async throws -> R {
        try await supabase.client.functions.invoke(
            "ai-suggest",
            options: FunctionInvokeOptions(body: body)
        )
    }
}
