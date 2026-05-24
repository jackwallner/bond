import Foundation

/// Messages exchanged between the watch and phone via `WCSession`.
public enum WatchPayload {
    /// Watch → phone: dictated reminder to be created on the phone.
    public static let createReminderKey = "wp.create_reminder"

    /// Who a dictated reminder is for. The phone resolves `.partner` to the
    /// actual partner id when paired, falling back to the user otherwise.
    public enum Recipient: String, Codable, Sendable, CaseIterable {
        case me, partner
    }

    public struct CreateReminder: Codable, Sendable {
        public let title: String
        public let loveLanguage: String   // LoveLanguage.rawValue
        public let scheduledOffsetSeconds: TimeInterval
        public let recipient: Recipient

        public init(
            title: String,
            loveLanguage: String,
            scheduledOffsetSeconds: TimeInterval,
            recipient: Recipient = .partner
        ) {
            self.title = title
            self.loveLanguage = loveLanguage
            self.scheduledOffsetSeconds = scheduledOffsetSeconds
            self.recipient = recipient
        }

        // Older watch builds omit `recipient`; default those to .partner to
        // match the new dictation default rather than failing to decode.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decode(String.self, forKey: .title)
            loveLanguage = try c.decode(String.self, forKey: .loveLanguage)
            scheduledOffsetSeconds = try c.decode(TimeInterval.self, forKey: .scheduledOffsetSeconds)
            recipient = try c.decodeIfPresent(Recipient.self, forKey: .recipient) ?? .partner
        }
    }
}
