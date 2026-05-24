import SwiftUI

struct ReminderRow: View {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    let reminder: ReminderDTO
    let currentUserId: UUID?
    let isActedOn: Bool

    init(reminder: ReminderDTO, currentUserId: UUID?, isActedOn: Bool = false) {
        self.reminder = reminder
        self.currentUserId = currentUserId
        self.isActedOn = isActedOn
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: reminder.loveLanguage.symbolName)
                .foregroundStyle(isActedOn ? .green : reminder.loveLanguage.tint)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(reminder.title)
                        .font(.bond(.headline))
                        .lineLimit(2)
                    if isActedOn {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.bond(.caption))
                            .foregroundStyle(.green)
                    }
                }
                if let body = reminder.body, !body.isEmpty {
                    Text(body)
                        .font(.bond(.subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    if let next = reminder.trigger?.upcomingFireDate() {
                        // Static relative string, formatted once at render. Using
                        // `Text(_, style: .relative)` here re-renders every second,
                        // which reads as a stopwatch the moment a reminder is set;
                        // a settled "in 3 hours" is calmer and matches the tone.
                        Text(Self.relativeFormatter.localizedString(for: next, relativeTo: Date()))
                            .font(.bond(.caption))
                            .foregroundStyle(.secondary)
                    }
                    if reminder.triggerType == "recurring",
                       let rrule = reminder.rrule,
                       let preset = RecurrencePreset(rrule: rrule) {
                        Text(preset.title)
                            .font(.bond(.caption2))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.gray.opacity(0.15), in: Capsule())
                    }
                    if reminder.targetId != currentUserId {
                        Text("for partner")
                            .font(.bond(.caption2))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(reminder.loveLanguage.tint.opacity(0.15), in: Capsule())
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .opacity(isActedOn ? 0.6 : 1)
    }
}
