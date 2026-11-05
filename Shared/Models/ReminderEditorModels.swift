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
