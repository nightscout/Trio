import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct TrioWatchComplicationEntry: TimelineEntry {
    let date: Date
    let glucoseValue: String
    let trend: String
    let delta: String
    let glucoseColor: Color
    let iob: String?
    let cob: String?
    let lastUpdateTime: Date?
    let units: String

    var isStale: Bool {
        guard let lastUpdate = lastUpdateTime else { return true }
        return Date().timeIntervalSince(lastUpdate) > 900 // 15 minutes
    }
}

// MARK: - Provider

struct TrioWatchComplicationProvider: TimelineProvider {
    func placeholder(in _: Context) -> TrioWatchComplicationEntry {
        TrioWatchComplicationEntry(
            date: Date(),
            glucoseValue: "120",
            trend: "→",
            delta: "+2",
            glucoseColor: .green,
            iob: "2.5U",
            cob: "30g",
            lastUpdateTime: Date(),
            units: "mg/dL"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TrioWatchComplicationEntry) -> Void) {
        let entry = loadLatestGlucoseFromAppGroup() ?? placeholder(in: context)
        completion(entry)
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TrioWatchComplicationEntry>) -> Void) {
        let currentEntry = loadLatestGlucoseFromAppGroup() ?? createPlaceholderEntry()

        // Update every 5 minutes to match CGM reading frequency
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        let timeline = Timeline(entries: [currentEntry], policy: .after(nextUpdate))

        completion(timeline)
    }

    // MARK: - Data Loading

    private func loadLatestGlucoseFromAppGroup() -> TrioWatchComplicationEntry? {
        guard let suiteName = Bundle.main.appGroupSuiteName,
              !suiteName.isEmpty,
              let sharedDefaults = UserDefaults(suiteName: suiteName)
        else {
            return nil
        }

        // Read glucose data from App Group (written by Watch app after receiving from iPhone)
        guard let glucoseValue = sharedDefaults.string(forKey: "currentGlucose"),
              !glucoseValue.isEmpty
        else {
            return nil
        }

        let trend = sharedDefaults.string(forKey: "trend") ?? ""
        let delta = sharedDefaults.string(forKey: "delta") ?? ""
        let colorString = sharedDefaults.string(forKey: "currentGlucoseColorString") ?? "#ffffff"

        let glucoseColor = Color(hex: colorString) ?? .white
        let lastUpdateTimestamp = sharedDefaults.double(forKey: "date")
        let lastUpdate = lastUpdateTimestamp > 0 ? Date(timeIntervalSince1970: lastUpdateTimestamp) : nil

        return TrioWatchComplicationEntry(
            date: Date(),
            glucoseValue: glucoseValue,
            trend: trend,
            delta: delta,
            glucoseColor: glucoseColor,
            iob: sharedDefaults.string(forKey: "iob"),
            cob: sharedDefaults.string(forKey: "cob"),
            lastUpdateTime: lastUpdate,
            units: sharedDefaults.string(forKey: "units") ?? "mg/dL"
        )
    }

    private func createPlaceholderEntry() -> TrioWatchComplicationEntry {
        TrioWatchComplicationEntry(
            date: Date(),
            glucoseValue: "--",
            trend: "",
            delta: "",
            glucoseColor: .gray,
            iob: nil,
            cob: nil,
            lastUpdateTime: nil,
            units: "mg/dL"
        )
    }
}

// MARK: - Views

/// Displayed View Wrapper
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
            // Fallback for unsupported families - show glucose text
            VStack {
                Text(entry.glucoseValue)
                    .font(.system(.body, design: .rounded))
                    .bold()
                Text(entry.trend)
                    .font(.caption)
            }
            .widgetBackground(backgroundView: Color.clear)
        }
    }
}

/// Circular Complication - Main glucose display
struct TrioAccessoryCircularView: View {
    var entry: TrioWatchComplicationEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()

            VStack(spacing: 1) {
                // Main glucose value
                Text(entry.isStale ? "--" : entry.glucoseValue)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.isStale ? .gray : entry.glucoseColor)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                // Trend + Delta
                HStack(spacing: 2) {
                    Text(entry.trend)
                        .font(.system(size: 12))
                        .foregroundStyle(entry.isStale ? .gray : .primary)
                    Text(entry.delta)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(4)
        }
    }
}

/// Corner Complication - Glucose in corner with trend/delta curving around
struct TrioAccessoryCornerView: View {
    var entry: TrioWatchComplicationEntry

    var body: some View {
        // Main content: just the glucose value, large and readable
        Text(entry.isStale ? "--" : entry.glucoseValue)
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundStyle(entry.isStale ? .gray : entry.glucoseColor)
            .widgetCurvesContent()
            .widgetLabel {
                // Curved label around the corner: trend + delta
                Text("\(entry.trend) \(entry.delta)")
            }
    }
}

/// Rectangular Complication - Full info display with IOB/COB
struct TrioAccessoryRectangularView: View {
    var entry: TrioWatchComplicationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Top row: Glucose + Trend + Delta
            HStack(spacing: 4) {
                Text(entry.isStale ? "--" : entry.glucoseValue)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.isStale ? .gray : entry.glucoseColor)

                Text(entry.trend)
                    .font(.system(size: 16))
                    .foregroundStyle(entry.isStale ? .gray : .primary)

                Text(entry.delta)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            // Bottom row: IOB + COB
            HStack(spacing: 12) {
                if let iob = entry.iob, !entry.isStale {
                    Text("IOB: \(iob)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                if let cob = entry.cob, !entry.isStale {
                    Text("COB: \(cob)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}

/// Inline Complication - Minimal glucose display
struct TrioAccessoryInlineView: View {
    var entry: TrioWatchComplicationEntry

    var body: some View {
        HStack(spacing: 3) {
            Text(entry.isStale ? "--" : entry.glucoseValue)
                .foregroundStyle(entry.isStale ? .gray : entry.glucoseColor)
            Text(entry.trend)
                .foregroundStyle(entry.isStale ? .gray : .primary)
            Text(entry.delta)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
    }
}

// MARK: - Widget Configuration

@main struct TrioWatchComplication: Widget {
    let kind: String = "TrioWatchComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrioWatchComplicationProvider()) { entry in
            TrioWatchComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Trio Glucose")
        .description("Real-time blood glucose monitoring with trend and delta")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - Extensions

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

extension Color {
    /// Initialize Color from hex string (supports #RRGGBB and #AARRGGBB formats)
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: // RGB (no alpha)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension Bundle {
    var appGroupSuiteName: String? {
        object(forInfoDictionaryKey: "AppGroupID") as? String
    }
}
