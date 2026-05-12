import Foundation

/// Messages exchanged between the watch and phone via `WCSession`.
public enum WatchPayload {
    /// Watch → phone: dictated reminder to be created on the phone.
    public static let createReminderKey = "wp.create_reminder"

    public struct CreateReminder: Codable, Sendable {
        public let title: String
        public let loveLanguage: String   // LoveLanguage.rawValue
        public let scheduledOffsetSeconds: TimeInterval

        public init(title: String, loveLanguage: String, scheduledOffsetSeconds: TimeInterval) {
            self.title = title
            self.loveLanguage = loveLanguage
            self.scheduledOffsetSeconds = scheduledOffsetSeconds
        }
    }
}
