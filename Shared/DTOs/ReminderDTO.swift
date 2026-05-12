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
            return .randomWindow(start: windowStart, end: windowEnd)
        default:
            return nil
        }
    }
}
