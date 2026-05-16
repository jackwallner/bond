import Foundation

public struct ReminderEventDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let reminderId: UUID
    public let coupleId: UUID
    public let firedAt: Date
    public var actedAt: Date?
    public var reaction: String?

    enum CodingKeys: String, CodingKey {
        case id
        case reminderId = "reminder_id"
        case coupleId = "couple_id"
        case firedAt = "fired_at"
        case actedAt = "acted_at"
        case reaction
    }
}
