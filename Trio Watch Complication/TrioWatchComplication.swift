import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct TrioWatchComplicationEntry: TimelineEntry {
    let date: Date
}

// MARK: - Provider

struct TrioWatchComplicationProvider: TimelineProvider {
    func placeholder(in _: Context) -> TrioWatchComplicationEntry {
        TrioWatchComplicationEntry(date: Date())
    }

    func getSnapshot(in _: Context, completion: @escaping (TrioWatchComplicationEntry) -> Void) {
        let entry = TrioWatchComplicationEntry(date: Date())
        completion(entry)
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TrioWatchComplicationEntry>) -> Void) {
        let entry = TrioWatchComplicationEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

// MARK: - Views

//// Displayed View Wrapper
struct TrioWatchComplicationEntryView: View {
    @Environment(\.widgetFamily) private var widgetFamily

    var entry: TrioWatchComplicationEntry

    var body: some View {
        switch widgetFamily {
        case .accessoryRectangular:
            TrioAccessoryRectangularView(entry: entry)
        case .accessoryCircular:
            TrioAccessoryCircularView(entry: entry)
        case .accessoryCorner:
            TrioAccessoryCornerView(entry: entry)
        case .accessoryInline:
            TrioAccessoryInlineView(entry: entry)
        default:
            Image("ComplicationIcon")
        }
    }
}

/// Corner Complication
struct TrioAccessoryCornerView: View {
    var entry: TrioWatchComplicationProvider.Entry

    var body: some View {
        Text("Trio")
            .font(.caption)
            .foregroundColor(.white)
    }
}

/// Circular Complication
struct TrioAccessoryCircularView: View {
    var entry: TrioWatchComplicationProvider.Entry

    var body: some View {
        Text("Trio")
            .font(.caption)
            .foregroundColor(.white)
    }
}

/// Rectangular Complication
struct TrioAccessoryRectangularView: View {
    var entry: TrioWatchComplicationProvider.Entry

    var body: some View {
        Text("Trio")
            .font(.headline)
            .foregroundColor(.primary)
    }
}

/// Inline Complication
struct TrioAccessoryInlineView: View {
    var entry: TrioWatchComplicationProvider.Entry

    var body: some View {
        Text("Trio")
            .font(.caption)
            .foregroundColor(.primary)
    }
}

// MARK: - Widget Configuration

@main struct TrioWatchComplication: Widget {
    let kind: String = "TrioWatchComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrioWatchComplicationProvider()) { entry in
            TrioWatchComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Trio")
        .description("Displays Trio app icon as complication")
        .supportedFamilies([
            .accessoryCorner,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}
