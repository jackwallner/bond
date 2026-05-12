import SwiftUI
import WidgetKit

@main
struct BondWidgetsBundle: WidgetBundle {
    var body: some Widget {
        UpcomingReminderWidget()
    }
}

struct UpcomingReminderWidget: Widget {
    let kind: String = "UpcomingReminderWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UpcomingReminderProvider()) { entry in
            UpcomingReminderView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Reminder")
        .description("Shows your next love-language reminder.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct UpcomingReminderEntry: TimelineEntry {
    let date: Date
    let title: String
    let language: LoveLanguage
}

struct UpcomingReminderProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpcomingReminderEntry {
        UpcomingReminderEntry(date: .now, title: "Tell her she's beautiful", language: .words)
    }

    func getSnapshot(in context: Context, completion: @escaping (UpcomingReminderEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingReminderEntry>) -> Void) {
        let entry = placeholder(in: context)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60 * 30))))
    }
}

struct UpcomingReminderView: View {
    let entry: UpcomingReminderEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: entry.language.symbolName)
                .foregroundStyle(entry.language.tint)
            Text(entry.title)
                .font(.callout.bold())
                .lineLimit(3)
            Spacer()
            Text(entry.date, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
