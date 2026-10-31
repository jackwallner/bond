import Foundation
import WidgetKit

@MainActor
enum WidgetSnapshotPump {
    /// Refreshes the App Group snapshot and asks WidgetKit to reload timelines.
    static func push(reminders: [ReminderDTO], milestones: [MilestoneDTO], userId: UUID?) {
        WidgetSnapshot.make(reminders: reminders, milestones: milestones, userId: userId).write()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Empties the App Group snapshot so widgets stop showing the previous
    /// account's data after sign-out or account deletion.
    static func clear() {
        WidgetSnapshot().write()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
