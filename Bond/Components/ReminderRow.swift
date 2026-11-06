import SwiftUI

struct ReminderRow: View {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    @Environment(\.dynamicTypeSize) private var typeSize

    let reminder: ReminderDTO
    let currentUserId: UUID?
    let isActedOn: Bool
    /// Tap handler for the leading check circle. Nil hides the affordance
    /// (e.g. read-only contexts) and falls back to the love-language glyph.
    var onToggleDone: (() -> Void)?

    init(
        reminder: ReminderDTO,
        currentUserId: UUID?,
        isActedOn: Bool = false,
        onToggleDone: (() -> Void)? = nil
    ) {
        self.reminder = reminder
        self.currentUserId = currentUserId
        self.isActedOn = isActedOn
        self.onToggleDone = onToggleDone
    }

    /// "Done today" / "Done this week" for repeating reminders; plain "Done"
    /// for one-shots.
    private var doneLabel: String {
        guard case .recurring(let rrule, _) = reminder.trigger,
              let preset = RecurrencePreset(rrule: rrule)
        else {
            return reminder.repeatsOnSchedule ? String(localized: "Done today") : String(localized: "Done")
        }
        switch preset {
        case .daily:   return String(localized: "Done today")
        case .weekly:  return String(localized: "Done this week")
        case .monthly: return String(localized: "Done this month")
        case .yearly:  return String(localized: "Done this year")
        }
    }

    /// At accessibility sizes the row reflows: the check circle sits above the
    /// text, nothing is cut to two lines, and the chips wrap onto their own lines.
    private var isLarge: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        HStack(spacing: 12) {
            // Inner block keeps icon top-aligned against multi-line content.
            // The outer HStack uses default (center) alignment so the chevron
            // sits vertically centered against the whole row - matching iOS
            // Reminders/Mail.
            let inner = isLarge
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            inner {
                checkCircle

                VStack(alignment: .leading, spacing: 4) {
                    Text(reminder.title)
                        .font(.bond(.headline))
                        .foregroundStyle(isActedOn ? AnyShapeStyle(.bondTextSecondary) : AnyShapeStyle(.primary))
                        .lineLimit(isLarge ? nil : 2)
                    if let body = reminder.body, !body.isEmpty {
                        Text(body)
                            .font(.bond(.subheadline))
                            .foregroundStyle(.bondTextSecondary)
                            .lineLimit(isLarge ? nil : 2)
                    }
                    FlowLayout(spacing: 8) {
                        if isActedOn {
                            Text(doneLabel)
                                .font(.bond(.caption, weight: .semibold))
                                .foregroundStyle(Color.bondDone)
                        } else if let next = reminder.trigger?.upcomingFireDate() {
                            // Static relative string, formatted once at render. Using
                            // `Text(_, style: .relative)` here re-renders every second,
                            // which reads as a stopwatch the moment a reminder is set;
                            // a settled "in 3 hours" is calmer and matches the tone.
                            Text(Self.relativeFormatter.localizedString(for: next, relativeTo: Date()))
                                .font(.bond(.caption))
                                .foregroundStyle(.bondTextSecondary)
                        }
                        if let cadence = cadenceLabel {
                            Text(cadence)
                                .font(.bond(.caption2))
                                .foregroundStyle(.bondTextSecondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.bondHairline, in: Capsule())
                        }
                        if reminder.targetId != currentUserId {
                            Text("for partner")
                                .font(.bond(.caption2))
                                .foregroundStyle(reminder.loveLanguage.textTint)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(reminder.loveLanguage.tint.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.bond(.caption, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityHint("Edit reminder")
    }

    private var cadenceLabel: String? {
        if case .randomRecurring = reminder.trigger { return String(localized: "Daily surprise") }
        guard reminder.triggerType == "recurring",
              let rrule = reminder.rrule,
              let preset = RecurrencePreset(rrule: rrule) else { return nil }
        return preset.title
    }

    /// Leading mark-done affordance: love-language glyph in a tinted ring
    /// when open, a filled green check when done. The whole circle is the
    /// tap target so completing doesn't require discovering the swipe.
    @ViewBuilder
    private var checkCircle: some View {
        if let onToggleDone {
            Button(action: onToggleDone) {
                circleContent
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isActedOn ? String(localized: "Mark as not done") : String(localized: "Mark as done"))
        } else {
            circleContent
        }
    }

    private var circleContent: some View {
        ZStack {
            if isActedOn {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.green)
            } else {
                Circle()
                    .strokeBorder(reminder.loveLanguage.tint.opacity(0.45), lineWidth: 1.5)
                Image(systemName: reminder.loveLanguage.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(reminder.loveLanguage.tint)
            }
        }
        .frame(width: 28, height: 28)
        .contentShape(Circle())
    }
}
