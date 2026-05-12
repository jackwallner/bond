import SwiftUI
import WidgetKit

@main
struct BondWidgetsBundle: WidgetBundle {
    var body: some Widget {
        UpcomingReminderWidget()
        AnniversaryCountdownWidget()
    }
}

// MARK: - Upcoming reminder

struct UpcomingReminderWidget: Widget {
    let kind = "UpcomingReminderWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UpcomingReminderProvider()) { entry in
            UpcomingReminderView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Reminder")
        .description("Your next love-language reminder.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct UpcomingReminderEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct UpcomingReminderProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpcomingReminderEntry {
        UpcomingReminderEntry(
            date: .now,
            snapshot: WidgetSnapshot(
                nextReminder: .init(
                    title: "Tell her she's beautiful",
                    fireAt: .now.addingTimeInterval(60 * 60),
                    loveLanguage: .words
                )
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (UpcomingReminderEntry) -> Void) {
        completion(UpcomingReminderEntry(date: .now, snapshot: WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingReminderEntry>) -> Void) {
        let entry = UpcomingReminderEntry(date: .now, snapshot: WidgetSnapshot.read())
        let next = entry.snapshot?.nextReminder?.fireAt ?? .now.addingTimeInterval(60 * 60)
        let refresh = max(.now.addingTimeInterval(60 * 15), next.addingTimeInterval(60))
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct UpcomingReminderView: View {
    let entry: UpcomingReminderEntry

    var body: some View {
        if let next = entry.snapshot?.nextReminder {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: next.loveLanguage.symbolName)
                    .foregroundStyle(next.loveLanguage.tint)
                Text(next.title)
                    .font(.callout.bold())
                    .lineLimit(3)
                Spacer(minLength: 0)
                Text(next.fireAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: "heart.text.square")
                    .foregroundStyle(.pink)
                Text("No reminders")
                    .font(.callout)
                Text("Add one in Bond")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Anniversary countdown

struct AnniversaryCountdownWidget: Widget {
    let kind = "AnniversaryCountdownWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AnniversaryProvider()) { entry in
            AnniversaryCountdownView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Milestone")
        .description("Countdown to your next anniversary or milestone.")
        .supportedFamilies([.systemSmall])
    }
}

struct AnniversaryEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct AnniversaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> AnniversaryEntry {
        AnniversaryEntry(
            date: .now,
            snapshot: WidgetSnapshot(
                nextMilestone: .init(
                    label: "Anniversary",
                    kind: "anniversary",
                    occursOn: .now.addingTimeInterval(60 * 60 * 24 * 60)
                )
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (AnniversaryEntry) -> Void) {
        completion(AnniversaryEntry(date: .now, snapshot: WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AnniversaryEntry>) -> Void) {
        let entry = AnniversaryEntry(date: .now, snapshot: WidgetSnapshot.read())
        completion(Timeline(
            entries: [entry],
            policy: .after(.now.addingTimeInterval(60 * 60 * 6))
        ))
    }
}

struct AnniversaryCountdownView: View {
    let entry: AnniversaryEntry

    var body: some View {
        if let m = entry.snapshot?.nextMilestone {
            let days = max(0, Calendar.current.dateComponents([.day], from: .now, to: m.occursOn).day ?? 0)
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: m.kind == "birthday" ? "gift.fill" : "heart.fill")
                    .foregroundStyle(.pink)
                Text(m.label)
                    .font(.caption.bold())
                Spacer(minLength: 0)
                Text("\(days)")
                    .font(.system(size: 36, weight: .bold))
                Text(days == 1 ? "day to go" : "days to go")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: "calendar.badge.plus")
                    .foregroundStyle(.pink)
                Text("Add a milestone")
                    .font(.caption.bold())
                    .multilineTextAlignment(.center)
            }
        }
    }
}
