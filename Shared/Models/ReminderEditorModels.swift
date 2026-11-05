import Foundation

enum ReminderTarget: String, CaseIterable, Identifiable {
    case me
    case partner

    var id: String { rawValue }
    var title: String { self == .me ? String(localized: "Me") : String(localized: "Partner") }
}

enum TriggerKind: String, CaseIterable, Identifiable {
    case oneTime
    case recurring
    case location
    case randomWindow

    var id: String { rawValue }
    var title: String {
        switch self {
        case .oneTime:      String(localized: "One time")
        case .recurring:    String(localized: "Recurring")
        case .location:     String(localized: "At a place")
        case .randomWindow: String(localized: "Random surprise")
        }
    }
    var subtitle: String {
        switch self {
        case .oneTime:      String(localized: "Fires once at a chosen moment.")
        case .recurring:    String(localized: "Daily, weekly, monthly. Your call.")
        case .location:     String(localized: "Triggers when you arrive somewhere.")
        case .randomWindow: String(localized: "A random moment: once, or at a random time every day.")
        }
    }
    var symbolName: String {
        switch self {
        case .oneTime:      "clock"
        case .recurring:    "repeat"
        case .location:     "mappin.and.ellipse"
        case .randomWindow: "sparkles"
        }
    }
    var isPremium: Bool {
        switch self {
        case .oneTime, .recurring: false
        case .location, .randomWindow: true
        }
    }
}

/// The default place name of a location reminder. The stored label is always
/// the English "Home" so the geofence written to Supabase does not depend on
/// the device language; the name field and preview show it translated. A name
/// the user typed is stored as typed.
public enum GeofenceLabel {
    public static let stableDefault = "Home"

    /// What the name field shows for a stored label.
    public static func display(_ stored: String, in bundle: Bundle = .main) -> String {
        stored == stableDefault ? shownDefault(in: bundle) : stored
    }

    /// The label to store for what the name field shows.
    public static func stored(_ shown: String, in bundle: Bundle = .main) -> String {
        shown == shownDefault(in: bundle) ? stableDefault : shown
    }

    private static func shownDefault(in bundle: Bundle) -> String {
        bundle.localizedString(forKey: stableDefault, value: stableDefault, table: nil)
    }
}
