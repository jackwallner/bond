import Foundation

public struct MilestoneDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let coupleId: UUID
    public var kind: String          // "anniversary" | "birthday" | "custom"
    public var label: String?
    public var date: Date            // calendar day (UTC midnight)
    public var recur: Bool
    public var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case coupleId  = "couple_id"
        case kind
        case label
        case date
        case recur
        case createdAt = "created_at"
    }

    public func nextOccurrence(reference: Date = .now, calendar: Calendar = .current) -> Date {
        guard recur else { return date }
        var comps = calendar.dateComponents([.month, .day], from: date)
        comps.year = calendar.component(.year, from: reference)

        // Feb 29 in non-leap years → roll to Mar 1
        var next = calendar.date(from: comps)
        if next == nil {
            comps.month = 3
            comps.day = 1
            next = calendar.date(from: comps)
        }

        guard var result = next else { return date }
        if result < reference {
            comps.year! += 1
            result = calendar.date(from: comps) ?? result
        }
        return result
    }
}
