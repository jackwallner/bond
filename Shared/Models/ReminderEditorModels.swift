enum ReminderTarget: String, CaseIterable, Identifiable {
    case me
    case partner

    var id: String { rawValue }
    var title: String { self == .me ? "Me" : "Partner" }
}

enum TriggerKind: String, CaseIterable, Identifiable {
    case oneTime
    case recurring
    case location
    case randomWindow

    var id: String { rawValue }
    var title: String {
        switch self {
        case .oneTime:      "One time"
        case .recurring:    "Recurring"
        case .location:     "At a place"
        case .randomWindow: "Random surprise"
        }
    }
    var subtitle: String {
        switch self {
        case .oneTime:      "Fires once at a chosen moment."
        case .recurring:    "Daily, weekly, monthly. Your call."
        case .location:     "Triggers when you arrive somewhere."
        case .randomWindow: "A random moment: once, or at a random time every day."
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
