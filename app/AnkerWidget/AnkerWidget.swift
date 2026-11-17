import SwiftUI
import WidgetKit

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, state: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, state: context.isPreview ? .placeholder : SharedStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let s = SharedStore.load()
        var entries = [Entry(date: .now, state: s)]
        // If the app stops sending, show the data as stale without a reload.
        if let s, s.connected {
            let staleAt = s.date.addingTimeInterval(SharedStore.staleAfter + 1)
            if staleAt > .now { entries.append(Entry(date: staleAt, state: s)) }
        }
        completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

@main
struct AnkerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AnkerWidget", provider: Provider()) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Anker Prime")
        .description("Charging power of each pad.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        ChargerWidgetContent(entry: entry, family: family)
            .containerBackground(for: .widget) {
                WidgetBackground(total: entry.stale ? 0 : entry.state?.total ?? 0)
            }
    }
}
