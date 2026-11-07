import SwiftUI
import WidgetKit

enum ComplicationContent {
    case reading(ComplicationState)
    case placeholder(ComplicationState)

    var state: ComplicationState {
        switch self {
        case let .placeholder(state),
             let .reading(state):
            return state
        }
    }

    var isPlaceholder: Bool {
        switch self {
        case .reading: return false
        case .placeholder: return true
        }
    }
}

struct TrioGlucoseEntry: TimelineEntry {
    let date: Date
    let content: ComplicationContent
}

struct TrioGlucoseProvider: TimelineProvider {
    private static let timelineStep: TimeInterval = 5 * 60
    private static let timelineSpan: TimeInterval = 2 * 60 * 60

    func placeholder(in _: Context) -> TrioGlucoseEntry {
        TrioGlucoseEntry(date: Date(), content: .placeholder(.placeholder))
    }

    func getSnapshot(in context: Context, completion: @escaping (TrioGlucoseEntry) -> Void) {
        if context.isPreview {
            completion(TrioGlucoseEntry(date: Date(), content: .placeholder(Self.preview)))
            return
        }
        completion(Self.currentEntry(at: Date()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TrioGlucoseEntry>) -> Void) {
        let now = Date()
        let current = Self.currentEntry(at: now)
        guard !current.content.isPlaceholder else {
            completion(Timeline(entries: [current], policy: .never))
            return
        }

        var dates = stride(from: 0, through: Self.timelineSpan, by: Self.timelineStep).map { now.addingTimeInterval($0) }
        let staleAt = current.content.state.date.addingTimeInterval(current.content.state.staleAfter + 1)
        if staleAt > now, staleAt < now.addingTimeInterval(Self.timelineSpan) {
            dates.append(staleAt)
        }
        let entries = dates.sorted().map { TrioGlucoseEntry(date: $0, content: current.content) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private static func currentEntry(at date: Date) -> TrioGlucoseEntry {
        if let state = ComplicationStore.load() {
            return TrioGlucoseEntry(date: date, content: .reading(state))
        }
        return TrioGlucoseEntry(date: date, content: .placeholder(.placeholder))
    }

    static var preview: ComplicationState {
        let units = ComplicationStore.load()?.units ?? ComplicationState.defaultUnits
        return ComplicationState.sample(units: units)
    }
}

struct TrioComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    let kind: ComplicationKind
    let entry: TrioGlucoseEntry

    var body: some View {
        let model = ComplicationModel(
            kind: kind,
            state: entry.content.state,
            rendering: ComplicationRendering(
                referenceDate: entry.date,
                isPlaceholder: entry.content.isPlaceholder,
                fullColor: renderingMode == .fullColor
            )
        )
        switch family {
        case .accessoryRectangular:
            ComplicationRectangularContent(model: model)
                .widgetAccentable()
                .widgetBackground(backgroundView: Color.clear)
        case .accessoryInline:
            ComplicationInlineContent(model: model)
                .widgetBackground(backgroundView: Color.clear)
        #if os(watchOS)
            case .accessoryCorner:
                ComplicationCornerMain(model: model)
                    .widgetAccentable()
                    .widgetCurvesContent()
                    .widgetLabel {
                        ComplicationCornerLabel(model: model)
                    }
                    .widgetBackground(backgroundView: Color.clear)
        #endif
        default:
            ZStack {
                if kind != .gauge {
                    AccessoryWidgetBackground()
                }
                ComplicationCircularContent(model: model)
                    .widgetAccentable()
            }
            .widgetBackground(backgroundView: Color.clear)
        }
    }
}

private func families(for kind: ComplicationKind) -> [WidgetFamily] {
    kind.slots.compactMap { slot -> WidgetFamily? in
        switch slot {
        case .circular: return .accessoryCircular
        case .rectangular: return .accessoryRectangular
        case .inline: return .accessoryInline
        case .corner:
            #if os(watchOS)
                return .accessoryCorner
            #else
                return nil
            #endif
        }
    }
}

private func complicationConfiguration(for kind: ComplicationKind) -> some WidgetConfiguration {
    StaticConfiguration(kind: kind.widgetKind, provider: TrioGlucoseProvider()) { entry in
        TrioComplicationEntryView(kind: kind, entry: entry)
    }
    .configurationDisplayName(kind.displayName)
    .description(kind.summary)
    .supportedFamilies(families(for: kind))
}

struct TrioGlucoseComplication: Widget {
    var body: some WidgetConfiguration { complicationConfiguration(for: .glucose) }
}

struct TrioGaugeComplication: Widget {
    var body: some WidgetConfiguration { complicationConfiguration(for: .gauge) }
}

struct TrioIobComplication: Widget {
    var body: some WidgetConfiguration { complicationConfiguration(for: .iob) }
}

struct TrioChartComplication: Widget {
    var body: some WidgetConfiguration { complicationConfiguration(for: .chart) }
}

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
        case .accessoryCircular:
            TrioAccessoryCircularView(entry: entry)
        #if os(watchOS)
            case .accessoryCorner:
                TrioAccessoryCornerView(entry: entry)
        #endif
        default:
            Image("ComplicationIcon")
                .widgetAccentable()
                .widgetBackground(backgroundView: Color.clear)
        }
    }
}

#if os(watchOS)
    /// Corner Complication
    struct TrioAccessoryCornerView: View {
        var entry: TrioWatchComplicationProvider.Entry

        var body: some View {
            Text("")
                .widgetCurvesContent()
                .widgetLabel {
                    Text("Trio")
                }
                .widgetBackground(backgroundView: Color.clear)
        }
    }
#endif

/// Circular Complication
struct TrioAccessoryCircularView: View {
    var entry: TrioWatchComplicationProvider.Entry

    var body: some View {
        Image("ComplicationIcon")
            .resizable()
            .widgetAccentable()
            .widgetBackground(backgroundView: Color.clear)
    }
}

// MARK: - Widget Configuration

struct TrioWatchComplication: Widget {
    let kind: String = "TrioWatchComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrioWatchComplicationProvider()) { entry in
            TrioWatchComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Trio")
        .description("Displays Trio app icon as complication")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        #if os(watchOS)
            return [.accessoryCorner, .accessoryCircular]
        #else
            return [.accessoryCircular]
        #endif
    }
}

@main struct TrioWatchComplicationBundle: WidgetBundle {
    var body: some Widget {
        TrioGlucoseComplication()
        TrioGaugeComplication()
        TrioIobComplication()
        TrioChartComplication()
        TrioWatchComplication()
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
