import Foundation

public struct MilestoneDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let coupleId: UUID
    public var kind: String          // "anniversary" | "birthday" | "custom"
    public var label: String?
    public var date: Date            // calendar day (local midnight)
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

    public init(
        id: UUID,
        coupleId: UUID,
        kind: String,
        label: String?,
        date: Date,
        recur: Bool,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.coupleId = coupleId
        self.kind = kind
        self.label = label
        self.date = date
        self.recur = recur
        self.createdAt = createdAt
    }

    // The `date` column is a Postgres `date` ("2026-03-05"), not a timestamp.
    // supabase-swift's default Date coding only speaks full ISO-8601
    // timestamps, so it throws on decode and shifts the calendar day across
    // timezones on encode. Code the field as a plain y-m-d string anchored to
    // the local calendar instead.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        coupleId = try c.decode(UUID.self, forKey: .coupleId)
        kind = try c.decode(String.self, forKey: .kind)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        recur = try c.decode(Bool.self, forKey: .recur)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)

        let raw = try c.decode(String.self, forKey: .date)
        let parts = raw.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let day = Calendar.current.date(
                  from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
              )
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .date, in: c, debugDescription: "Invalid date: \(raw)"
            )
        }
        date = day
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(coupleId, forKey: .coupleId)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encode(recur, forKey: .recur)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)

        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", comps.year!, comps.month!, comps.day!)
        try c.encode(day, forKey: .date)
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
