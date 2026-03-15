import SwiftUI
import WidgetKit

// MARK: - Shared Data Storage

struct ComplicationData {
    static var appGroupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String
    }

    private static var sharedDefaults: UserDefaults? {
        guard let groupID = appGroupID else { return nil }
        return UserDefaults(suiteName: groupID)
    }

    static var glucose: String {
        sharedDefaults?.string(forKey: "complication_glucose") ?? "--"
    }

    static var trend: String {
        sharedDefaults?.string(forKey: "complication_trend") ?? ""
    }

    static var delta: String {
        sharedDefaults?.string(forKey: "complication_delta") ?? ""
    }

    static var iob: String {
        sharedDefaults?.string(forKey: "complication_iob") ?? ""
    }

    static var cob: String {
        sharedDefaults?.string(forKey: "complication_cob") ?? ""
    }

    static var lastUpdate: Date {
        sharedDefaults?.object(forKey: "complication_lastUpdate") as? Date ?? .distantPast
    }

    static var isStale: Bool {
        Date().timeIntervalSince(lastUpdate) > 600 // 10 minutes
    }
}

// MARK: - Timeline Entry

struct TrioWatchComplicationEntry: TimelineEntry {
    let date: Date
    let glucose: String
    let trend: String
    let delta: String
    let iob: String
    let cob: String
    let isStale: Bool
}

// MARK: - Provider

struct TrioWatchComplicationProvider: TimelineProvider {
    func placeholder(in _: Context) -> TrioWatchComplicationEntry {
        TrioWatchComplicationEntry(
            date: Date(),
            glucose: "120",
            trend: "→",
            delta: "+2",
            iob: "1.5",
            cob: "20",
            isStale: false
        )
    }

    func getSnapshot(in _: Context, completion: @escaping (TrioWatchComplicationEntry) -> Void) {
        let entry = TrioWatchComplicationEntry(
            date: Date(),
            glucose: ComplicationData.glucose,
            trend: ComplicationData.trend,
            delta: ComplicationData.delta,
            iob: ComplicationData.iob,
            cob: ComplicationData.cob,
            isStale: ComplicationData.isStale
        )
        completion(entry)
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TrioWatchComplicationEntry>) -> Void) {
        let entry = TrioWatchComplicationEntry(
            date: Date(),
            glucose: ComplicationData.glucose,
            trend: ComplicationData.trend,
            delta: ComplicationData.delta,
            iob: ComplicationData.iob,
            cob: ComplicationData.cob,
            isStale: ComplicationData.isStale
        )
        // Refresh every 5 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Views

struct TrioWatchComplicationEntryView: View {
    @Environment(\.widgetFamily) private var widgetFamily

    var entry: TrioWatchComplicationEntry

    var body: some View {
        switch widgetFamily {
        case .accessoryCircular:
            TrioAccessoryCircularView(entry: entry)
        case .accessoryCorner:
            TrioAccessoryCornerView(entry: entry)
        case .accessoryRectangular:
            TrioAccessoryRectangularView(entry: entry)
        case .accessoryInline:
            TrioAccessoryInlineView(entry: entry)
        default:
            Image("ComplicationIcon")
                .widgetAccentable()
                .widgetBackground(backgroundView: Color.clear)
        }
    }
}

/// Corner Complication - Shows glucose + trend
struct TrioAccessoryCornerView: View {
    var entry: TrioWatchComplicationEntry

    var body: some View {
        Text(entry.glucose)
            .font(.system(.title2, design: .rounded).weight(.semibold))
            .foregroundColor(entry.isStale ? .gray : .primary)
            .widgetCurvesContent()
            .widgetLabel {
                Text("\(entry.trend) \(entry.delta)")
            }
            .widgetBackground(backgroundView: Color.clear)
    }
}

/// Circular Complication - Shows glucose with trend
struct TrioAccessoryCircularView: View {
    var entry: TrioWatchComplicationEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(entry.glucose)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6)
                Text(entry.trend)
                    .font(.caption2)
            }
            .foregroundColor(entry.isStale ? .gray : .primary)
        }
        .widgetBackground(backgroundView: Color.clear)
    }
}

/// Rectangular Complication - Shows glucose, trend, delta, IOB, COB
struct TrioAccessoryRectangularView: View {
    var entry: TrioWatchComplicationEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.glucose)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Text(entry.trend)
                        .font(.title3)
                    Text(entry.delta)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 8) {
                    Label(entry.iob, systemImage: "drop.fill")
                        .font(.caption2)
                    Label(entry.cob, systemImage: "fork.knife")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
            Spacer()
        }
        .foregroundColor(entry.isStale ? .gray : .primary)
        .widgetBackground(backgroundView: Color.clear)
    }
}

/// Inline Complication - Single line glucose + trend
struct TrioAccessoryInlineView: View {
    var entry: TrioWatchComplicationEntry

    var body: some View {
        Text("\(entry.glucose) \(entry.trend) \(entry.delta)")
            .foregroundColor(entry.isStale ? .gray : .primary)
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
        .description("Displays glucose, trend, IOB, and COB")
        .supportedFamilies([
            .accessoryCorner,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

extension View {
    func widgetBackground(backgroundView: some View) -> some View {
        if #available(watchOS 10.0, iOSApplicationExtension 17.0, iOS 17.0, *) {
            return containerBackground(for: .widget) {
                backgroundView
            }
        } else {
            return background(backgroundView)
        }
    }
}
