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
    var isPremium: Bool {
        switch self {
        case .oneTime, .recurring: false
        case .location, .randomWindow: true
        }
    }
}
