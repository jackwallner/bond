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
            TemplateReminder(id: "da_1", title: String(localized: "Morning Affirmation"), body: String(localized: "Start the day with a loving message"), loveLanguage: .words, triggerRecurrence: .daily),
            TemplateReminder(id: "da_2", title: String(localized: "Goodnight Text"), body: String(localized: "A sweet goodnight message"), loveLanguage: .words, triggerRecurrence: .daily),
            TemplateReminder(id: "da_3", title: String(localized: "Weekend Love Note"), body: String(localized: "A heartfelt note for the weekend"), loveLanguage: .words, triggerRecurrence: .weekly),
        ]
    ) }

    public static var dateNight: ReminderTemplateGroup { ReminderTemplateGroup(
        id: "date_night",
        title: String(localized: "Date Night"),
        subtitle: String(localized: "Keep the romance alive"),
        icon: "sparkles",
        reminders: [
            TemplateReminder(id: "dn_1", title: String(localized: "Plan a Date Night"), body: String(localized: "Set aside quality time this week"), loveLanguage: .time, triggerRecurrence: .weekly),
            TemplateReminder(id: "dn_2", title: String(localized: "Try Something New"), body: String(localized: "Explore a new activity together"), loveLanguage: .time, triggerRecurrence: .monthly),
            TemplateReminder(id: "dn_3", title: String(localized: "Surprise Gesture"), body: String(localized: "A small surprise to show you care"), loveLanguage: .gifts, triggerRecurrence: .monthly),
        ]
    ) }

    public static var longDistance: ReminderTemplateGroup { ReminderTemplateGroup(
        id: "long_distance",
        title: String(localized: "Long Distance"),
        subtitle: String(localized: "Stay close from afar"),
        icon: "airplane",
        reminders: [
            TemplateReminder(id: "ld_1", title: String(localized: "Morning Check-In"), body: String(localized: "Say good morning even from far away"), loveLanguage: .words, triggerRecurrence: .daily),
            TemplateReminder(id: "ld_2", title: String(localized: "Video Call Reminder"), body: String(localized: "Time for a face-to-face chat"), loveLanguage: .time, triggerRecurrence: .weekly),
            TemplateReminder(id: "ld_3", title: String(localized: "Send a Care Package"), body: String(localized: "Mail a little surprise"), loveLanguage: .gifts, triggerRecurrence: .monthly),
            TemplateReminder(id: "ld_4", title: String(localized: "Virtual Movie Night"), body: String(localized: "Pick a movie and watch together"), loveLanguage: .time, triggerRecurrence: .weekly),
        ]
    ) }

    public static var newParents: ReminderTemplateGroup { ReminderTemplateGroup(
        id: "new_parents",
        title: String(localized: "New Parents"),
        subtitle: String(localized: "Nurture your connection"),
        icon: "figure.and.child.holdinghands",
        reminders: [
            TemplateReminder(id: "np_1", title: String(localized: "Check In with Each Other"), body: String(localized: "How are we both doing today?"), loveLanguage: .words, triggerRecurrence: .daily),
            TemplateReminder(id: "np_2", title: String(localized: "10 Minutes Just Us"), body: String(localized: "Find 10 minutes for just the two of you"), loveLanguage: .time, triggerRecurrence: .daily),
            TemplateReminder(id: "np_3", title: String(localized: "Share the Load"), body: String(localized: "Take one task off your partner's plate today"), loveLanguage: .acts, triggerRecurrence: .daily),
            TemplateReminder(id: "np_4", title: String(localized: "Hug and Breathe"), body: String(localized: "A long hug and a deep breath together"), loveLanguage: .touch, triggerRecurrence: .daily),
        ]
    ) }

    public static var appreciation: ReminderTemplateGroup { ReminderTemplateGroup(
        id: "appreciation",
        title: String(localized: "Daily Appreciation"),
        subtitle: String(localized: "Never take each other for granted"),
        icon: "heart.fill",
        reminders: [
            TemplateReminder(id: "ap_1", title: String(localized: "Thank Your Partner"), body: String(localized: "Say thank you for something specific today"), loveLanguage: .words, triggerRecurrence: .daily),
            TemplateReminder(id: "ap_2", title: String(localized: "Notice the Little Things"), body: String(localized: "Compliment something small your partner did"), loveLanguage: .words, triggerRecurrence: .daily),
            TemplateReminder(id: "ap_3", title: String(localized: "Love Note"), body: String(localized: "Leave a note where your partner will find it"), loveLanguage: .words, triggerRecurrence: .weekly),
        ]
    ) }

    public static var actsOfService: ReminderTemplateGroup { ReminderTemplateGroup(
        id: "acts_of_service",
        title: String(localized: "Acts of Service"),
        subtitle: String(localized: "Show love through actions"),
        icon: "hands.sparkles.fill",
        reminders: [
            TemplateReminder(id: "as_1", title: String(localized: "Make Them Breakfast"), body: String(localized: "Start their day with a made-with-love meal"), loveLanguage: .acts, triggerRecurrence: .weekly),
            TemplateReminder(id: "as_2", title: String(localized: "Take Care of a Chore"), body: String(localized: "Handle something on their to-do list"), loveLanguage: .acts, triggerRecurrence: .weekly),
            TemplateReminder(id: "as_3", title: String(localized: "Fill Up the Car"), body: String(localized: "A small act that saves them time"), loveLanguage: .acts, triggerRecurrence: .weekly),
            TemplateReminder(id: "as_4", title: String(localized: "Run Their Errand"), body: String(localized: "Take care of one errand for them today"), loveLanguage: .acts, triggerRecurrence: .weekly),
        ]
    ) }
}
