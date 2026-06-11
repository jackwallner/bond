import Foundation
import WidgetKit

@MainActor
enum WidgetSnapshotPump {
    /// Refreshes the App Group snapshot and asks WidgetKit to reload timelines.
    static func push(reminders: [ReminderDTO], milestones: [MilestoneDTO]) {
        let nextReminder = reminders
            .compactMap { r -> (ReminderDTO, Date)? in
                guard let fire = r.trigger?.upcomingFireDate(), fire > .now else { return nil }
                return (r, fire)
            }
            .min { $0.1 < $1.1 }
            .map { tuple in
                WidgetSnapshot.NextReminder(
                    title: tuple.0.title,
                    fireAt: tuple.1,
                    loveLanguage: tuple.0.loveLanguage
                )
            }

        let nextMilestone = milestones
            .map { ($0, $0.nextOccurrence()) }
            .min { $0.1 < $1.1 }
            .map { tuple in
                WidgetSnapshot.NextMilestone(
                    label: tuple.0.label ?? defaultLabel(for: tuple.0),
                    kind: tuple.0.kind,
                    occursOn: tuple.1
                )
            }

        WidgetSnapshot(nextReminder: nextReminder, nextMilestone: nextMilestone).write()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Empties the App Group snapshot so widgets stop showing the previous
    /// account's data after sign-out or account deletion.
    static func clear() {
        WidgetSnapshot().write()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func defaultLabel(for m: MilestoneDTO) -> String {
        switch m.kind {
        case "anniversary": "Anniversary"
        case "birthday":    "Birthday"
        default:            "Milestone"
        }
    }
}
