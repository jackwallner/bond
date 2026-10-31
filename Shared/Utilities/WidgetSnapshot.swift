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

        /// Calendar days from `reference` to `occursOn`, floored at zero.
        public func daysAway(from reference: Date = .now, calendar: Calendar = .current) -> Int {
            let from = calendar.startOfDay(for: reference)
            let to = calendar.startOfDay(for: occursOn)
            return max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
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

public extension WidgetSnapshot {
    /// What the widgets show, built from the couple's lists. `userId` is who is signed
    /// in on this phone.
    static func make(
        reminders: [ReminderDTO],
        milestones: [MilestoneDTO],
        userId: UUID?,
        now: Date = .now
    ) -> WidgetSnapshot {
        let nextReminder = reminders
            .compactMap { r -> (ReminderDTO, Date)? in
                guard let fire = r.trigger?.upcomingFireDate(after: now), fire > now else { return nil }
                return (r, fire)
            }
            .min { $0.1 < $1.1 }
            .map { tuple in
                NextReminder(
                    title: tuple.0.title,
                    fireAt: tuple.1,
                    loveLanguage: tuple.0.loveLanguage
                )
            }

        let nextMilestone = milestones
            .map { ($0, $0.nextOccurrence(reference: now)) }
            .min { $0.1 < $1.1 }
            .map { tuple in
                NextMilestone(
                    label: tuple.0.label ?? defaultLabel(for: tuple.0),
                    kind: tuple.0.kind,
                    occursOn: tuple.1
                )
            }

        return WidgetSnapshot(nextReminder: nextReminder, nextMilestone: nextMilestone, updatedAt: now)
    }

    private static func defaultLabel(for m: MilestoneDTO) -> String {
        switch m.kind {
        case "anniversary": "Anniversary"
        case "birthday":    "Birthday"
        default:            "Milestone"
        }
    }
}
