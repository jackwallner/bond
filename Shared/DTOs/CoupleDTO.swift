import Foundation

public struct CoupleDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let partnerA: UUID
    public let partnerB: UUID
    public let pairedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case partnerA = "partner_a"
        case partnerB = "partner_b"
        case pairedAt = "paired_at"
    }

    public func partnerId(forSelf userId: UUID) -> UUID? {
        if partnerA == userId { return partnerB }
        if partnerB == userId { return partnerA }
        return nil
    }
}

public struct InviteCodeDTO: Codable, Sendable, Hashable {
    public let code: String
    public let createdBy: UUID
    public let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case code
        case createdBy = "created_by"
        case expiresAt = "expires_at"
    }
}
