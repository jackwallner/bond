import Foundation

public struct DailyQuestionDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let question: String
    public let category: String
    public let loveLanguage: LoveLanguage?

    enum CodingKeys: String, CodingKey {
        case id
        case question
        case category
        case loveLanguage = "love_language"
    }
}

public struct QuestionResponseDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let questionId: UUID
    public let coupleId: UUID
    public let userId: UUID
    public let response: String
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case questionId = "question_id"
        case coupleId = "couple_id"
        case userId = "user_id"
        case response
        case createdAt = "created_at"
    }
}
