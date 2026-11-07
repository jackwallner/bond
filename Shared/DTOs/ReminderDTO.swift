import Foundation

public struct ReminderDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let coupleId: UUID
    public let authorId: UUID
    public var targetId: UUID
    public var title: String
    public var body: String?
    public var loveLanguage: LoveLanguage
    public var triggerType: String
    public var fireAt: Date?
    public var rrule: String?
    public var geofence: Geofence?
    public var windowStart: Date?
    public var windowEnd: Date?
    public var status: String
    public var surpriseHiddenFromPartner: Bool
    public var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case coupleId      = "couple_id"
        case authorId      = "author_id"
        case targetId      = "target_id"
        case title
        case body
        case loveLanguage  = "love_language"
        case triggerType   = "trigger_type"
        case fireAt        = "fire_at"
        case rrule
        case geofence
        case windowStart   = "window_start"
        case windowEnd     = "window_end"
        case status
        case surpriseHiddenFromPartner = "surprise_hidden_from_partner"
        case createdAt     = "created_at"
    }

    // The synthesized encoder leaves a nil field out of the body, and an upsert
    // only changes the columns that are in its body: clearing the note, turning
    // off a repeat rule or switching the trigger kind would silently keep the old
    // value on the server. Cleared fields go out as explicit nulls instead.
    // `created_at` stays out when unknown, so the database default applies.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(coupleId, forKey: .coupleId)
        try c.encode(authorId, forKey: .authorId)
        try c.encode(targetId, forKey: .targetId)
        try c.encode(title, forKey: .title)
        try c.encode(body, forKey: .body)
        try c.encode(loveLanguage, forKey: .loveLanguage)
        try c.encode(triggerType, forKey: .triggerType)
        try c.encode(fireAt, forKey: .fireAt)
        try c.encode(rrule, forKey: .rrule)
        try c.encode(geofence, forKey: .geofence)
        try c.encode(windowStart, forKey: .windowStart)
        try c.encode(windowEnd, forKey: .windowEnd)
        try c.encode(status, forKey: .status)
        try c.encode(surpriseHiddenFromPartner, forKey: .surpriseHiddenFromPartner)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
    }

    public var trigger: ReminderTrigger? {
        switch triggerType {
        case "one_time":
            guard let fireAt else { return nil }
            return .oneTime(fireAt: fireAt)
        case "recurring":
            guard let rrule, let fireAt else { return nil }
            return .recurring(rrule: rrule, nextFire: fireAt)
        case "location":
            guard let geofence else { return nil }
            return .location(geofence: geofence, onEntry: true)
        case "random_window":
            guard let windowStart, let windowEnd else { return nil }
            // A repeating rule turns the absolute window into a daily
            // time-of-day window ("random time between 6 and 9 every day").
            if rrule != nil {
                return .randomRecurring(start: windowStart, end: windowEnd)
            }
            return .randomWindow(start: windowStart, end: windowEnd)
        default:
            return nil
        }
    }
}

public extension ReminderDTO {
    /// This row with another copy's schedule: what `reschedule_reminder` changes
    /// on a reminder the partner wrote, and nothing else.
    func withSchedule(of other: ReminderDTO) -> ReminderDTO {
        var row = self
        row.triggerType = other.triggerType
        row.fireAt = other.fireAt
        row.rrule = other.rrule
        row.geofence = other.geofence
        row.windowStart = other.windowStart
        row.windowEnd = other.windowEnd
        return row
    }

    /// The reminders this user sees: the ones they wrote and the ones addressed
    /// to them. The couple's rows are all readable, and the partner's own
    /// reminders (including the private ones) are not for this user.
    static func visible(_ reminders: [ReminderDTO], to user: UUID?) -> [ReminderDTO] {
        guard let user else { return [] }
        return reminders.filter { $0.authorId == user || $0.targetId == user }
    }
}
