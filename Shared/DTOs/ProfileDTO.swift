import Foundation

public struct ProfileDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var displayName: String?
    public var avatarUrl: String?
    public var apnsToken: String?
    public var loveLanguage: String?
    public var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName  = "display_name"
        case avatarUrl    = "avatar_url"
        case apnsToken    = "apns_token"
        case loveLanguage = "love_language"
        case createdAt    = "created_at"
    }
}
