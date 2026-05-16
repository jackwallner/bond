import SwiftUI

struct ReminderRow: View {
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
                        .font(.headline)
                        .lineLimit(2)
                    if isActedOn {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                if let body = reminder.body, !body.isEmpty {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    if let next = reminder.trigger?.upcomingFireDate() {
                        Text(next, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if reminder.triggerType == "recurring",
                       let rrule = reminder.rrule,
                       let preset = RecurrencePreset(rrule: rrule) {
                        Text(preset.title)
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.gray.opacity(0.15), in: Capsule())
                    }
                    if reminder.targetId != currentUserId {
                        Text("for partner")
                            .font(.caption2)
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
