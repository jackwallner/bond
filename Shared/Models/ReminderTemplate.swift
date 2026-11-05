import Foundation

public struct ReminderTemplateGroup: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let icon: String
    public let reminders: [TemplateReminder]

    public init(id: String, title: String, subtitle: String, icon: String, reminders: [TemplateReminder]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.reminders = reminders
    }
}

/// `title` and `body` are the stable English text a template writes into a new
/// reminder (and so into Supabase), whatever language the importing device
/// uses. They are also the catalog keys. Screens show `displayTitle` and
/// `displayBody`, which resolve those keys in the active language.
public struct TemplateReminder: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let body: String?
    public let loveLanguage: LoveLanguage
    public let triggerRecurrence: RecurrencePreset?

    public init(id: String, title: String, body: String?, loveLanguage: LoveLanguage, triggerRecurrence: RecurrencePreset?) {
        self.id = id
        self.title = title
        self.body = body
        self.loveLanguage = loveLanguage
        self.triggerRecurrence = triggerRecurrence
    }

    public var displayTitle: String { Self.display(title) }
    public var displayBody: String? { body.map { Self.display($0) } }

    /// The catalog's text for a stable English key in the active language.
    /// Missing keys fall back to the English key itself.
    static func display(_ key: String, in bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

public enum ReminderTemplateStore {
    public static var groups: [ReminderTemplateGroup] {
        [
            dailyAffirmations,
            dateNight,
            longDistance,
            newParents,
            appreciation,
            actsOfService,
        ]
    }

    public static var dailyAffirmations: ReminderTemplateGroup { ReminderTemplateGroup(
        id: "daily_affirmations",
        title: String(localized: "Daily Affirmations"),
        subtitle: String(localized: "Send loving words every day"),
        icon: "quote.bubble.fill",
        reminders: [
            TemplateReminder(id: "da_1", title: "Morning Affirmation", body: "Start the day with a loving message", loveLanguage: .words, triggerRecurrence: .daily),
            TemplateReminder(id: "da_2", title: "Goodnight Text", body: "A sweet goodnight message", loveLanguage: .words, triggerRecurrence: .daily),
            TemplateReminder(id: "da_3", title: "Weekend Love Note", body: "A heartfelt note for the weekend", loveLanguage: .words, triggerRecurrence: .weekly),
        ]
    ) }

    public static var dateNight: ReminderTemplateGroup { ReminderTemplateGroup(
        id: "date_night",
        title: String(localized: "Date Night"),
        subtitle: String(localized: "Keep the romance alive"),
        icon: "sparkles",
        reminders: [
            TemplateReminder(id: "dn_1", title: "Plan a Date Night", body: "Set aside quality time this week", loveLanguage: .time, triggerRecurrence: .weekly),
            TemplateReminder(id: "dn_2", title: "Try Something New", body: "Explore a new activity together", loveLanguage: .time, triggerRecurrence: .monthly),
            TemplateReminder(id: "dn_3", title: "Surprise Gesture", body: "A small surprise to show you care", loveLanguage: .gifts, triggerRecurrence: .monthly),
        ]
    ) }

    public static var longDistance: ReminderTemplateGroup { ReminderTemplateGroup(
        id: "long_distance",
        title: String(localized: "Long Distance"),
        subtitle: String(localized: "Stay close from afar"),
        icon: "airplane",
        reminders: [
            TemplateReminder(id: "ld_1", title: "Morning Check-In", body: "Say good morning even from far away", loveLanguage: .words, triggerRecurrence: .daily),
            TemplateReminder(id: "ld_2", title: "Video Call Reminder", body: "Time for a face-to-face chat", loveLanguage: .time, triggerRecurrence: .weekly),
            TemplateReminder(id: "ld_3", title: "Send a Care Package", body: "Mail a little surprise", loveLanguage: .gifts, triggerRecurrence: .monthly),
            TemplateReminder(id: "ld_4", title: "Virtual Movie Night", body: "Pick a movie and watch together", loveLanguage: .time, triggerRecurrence: .weekly),
        ]
    ) }

    public static var newParents: ReminderTemplateGroup { ReminderTemplateGroup(
        id: "new_parents",
        title: String(localized: "New Parents"),
        subtitle: String(localized: "Nurture your connection"),
        icon: "figure.and.child.holdinghands",
        reminders: [
            TemplateReminder(id: "np_1", title: "Check In with Each Other", body: "How are we both doing today?", loveLanguage: .words, triggerRecurrence: .daily),
            TemplateReminder(id: "np_2", title: "10 Minutes Just Us", body: "Find 10 minutes for just the two of you", loveLanguage: .time, triggerRecurrence: .daily),
            TemplateReminder(id: "np_3", title: "Share the Load", body: "Take one task off your partner's plate today", loveLanguage: .acts, triggerRecurrence: .daily),
            TemplateReminder(id: "np_4", title: "Hug and Breathe", body: "A long hug and a deep breath together", loveLanguage: .touch, triggerRecurrence: .daily),
        ]
    ) }

    public static var appreciation: ReminderTemplateGroup { ReminderTemplateGroup(
        id: "appreciation",
        title: String(localized: "Daily Appreciation"),
        subtitle: String(localized: "Never take each other for granted"),
        icon: "heart.fill",
        reminders: [
            TemplateReminder(id: "ap_1", title: "Thank Your Partner", body: "Say thank you for something specific today", loveLanguage: .words, triggerRecurrence: .daily),
            TemplateReminder(id: "ap_2", title: "Notice the Little Things", body: "Compliment something small your partner did", loveLanguage: .words, triggerRecurrence: .daily),
            TemplateReminder(id: "ap_3", title: "Love Note", body: "Leave a note where your partner will find it", loveLanguage: .words, triggerRecurrence: .weekly),
        ]
    ) }

    public static var actsOfService: ReminderTemplateGroup { ReminderTemplateGroup(
        id: "acts_of_service",
        title: String(localized: "Acts of Service"),
        subtitle: String(localized: "Show love through actions"),
        icon: "hands.sparkles.fill",
        reminders: [
            TemplateReminder(id: "as_1", title: "Make Them Breakfast", body: "Start their day with a made-with-love meal", loveLanguage: .acts, triggerRecurrence: .weekly),
            TemplateReminder(id: "as_2", title: "Take Care of a Chore", body: "Handle something on their to-do list", loveLanguage: .acts, triggerRecurrence: .weekly),
            TemplateReminder(id: "as_3", title: "Fill Up the Car", body: "A small act that saves them time", loveLanguage: .acts, triggerRecurrence: .weekly),
            TemplateReminder(id: "as_4", title: "Run Their Errand", body: "Take care of one errand for them today", loveLanguage: .acts, triggerRecurrence: .weekly),
        ]
    ) }
}
