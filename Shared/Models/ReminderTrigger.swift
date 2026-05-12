import Foundation

public enum ReminderTrigger: Codable, Sendable, Hashable {
    case oneTime(fireAt: Date)
    case recurring(rrule: String, nextFire: Date)
    case location(geofence: Geofence, onEntry: Bool)
    case randomWindow(start: Date, end: Date)

    public var kindRaw: String {
        switch self {
        case .oneTime:      "one_time"
        case .recurring:    "recurring"
        case .location:     "location"
        case .randomWindow: "random_window"
        }
    }

    public var nextFireDate: Date? {
        switch self {
        case .oneTime(let d):        d
        case .recurring(_, let d):   d
        case .randomWindow(_, let e): e
        case .location:              nil
        }
    }
}

public struct Geofence: Codable, Sendable, Hashable {
    public let latitude: Double
    public let longitude: Double
    public let radiusMeters: Double
    public let label: String

    public init(latitude: Double, longitude: Double, radiusMeters: Double, label: String) {
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.label = label
    }
}
