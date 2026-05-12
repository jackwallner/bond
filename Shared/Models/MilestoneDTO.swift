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
        guard var next = calendar.date(from: comps) else { return date }
        if next < calendar.startOfDay(for: reference) {
            next = calendar.date(byAdding: .year, value: 1, to: next) ?? next
        }
        return next
    }
}
