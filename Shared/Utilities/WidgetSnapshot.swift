import Foundation

/// Codable snapshot the iOS app writes into the App Group UserDefaults
/// so widget timelines can read live data without hitting Supabase.
public struct WidgetSnapshot: Codable, Sendable {
    public static let key = "widget.snapshot.v1"

    public var nextReminder: NextReminder?
    public var nextMilestone: NextMilestone?
    public var updatedAt: Date

    public init(
        nextReminder: NextReminder? = nil,
        nextMilestone: NextMilestone? = nil,
        updatedAt: Date = .now
    ) {
        self.nextReminder = nextReminder
        self.nextMilestone = nextMilestone
        self.updatedAt = updatedAt
    }

    public struct NextReminder: Codable, Sendable {
        public let title: String
        public let fireAt: Date
        public let loveLanguageRaw: String
        public var loveLanguage: LoveLanguage { LoveLanguage(rawValue: loveLanguageRaw) ?? .words }

        public init(title: String, fireAt: Date, loveLanguage: LoveLanguage) {
            self.title = title
            self.fireAt = fireAt
            self.loveLanguageRaw = loveLanguage.rawValue
        }
    }

    public struct NextMilestone: Codable, Sendable {
        public let label: String
        public let kind: String
        public let occursOn: Date

        public init(label: String, kind: String, occursOn: Date) {
            self.label = label
            self.kind = kind
            self.occursOn = occursOn
        }
    }

    public static func read() -> WidgetSnapshot? {
        guard let data = AppGroup.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func write() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        AppGroup.defaults.set(data, forKey: Self.key)
    }
}
