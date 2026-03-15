import SwiftUI
import WidgetKit

// MARK: - App Group Helper

/// Returns the App Group suite name for sharing data between Watch app and complications
private func getAppGroupSuiteName() -> String? {
    guard let bundleId = Bundle.main.bundleIdentifier else { return nil }
    // Bundle ID format: org.nightscout.TEAMID.trio.watchkitapp.TrioWatchComplication
    // App Group format: group.org.nightscout.TEAMID.trio.trio-app-group
    let components = bundleId.components(separatedBy: ".")
    // Find the base: org.nightscout.TEAMID.trio
    if let trioIndex = components.firstIndex(of: "trio"), trioIndex >= 3 {
        let base = components[0...trioIndex].joined(separator: ".")
        return "group.\(base).trio-app-group"
    }
    return nil
}

/// Shared UserDefaults for Watch app and complications
private var sharedUserDefaults: UserDefaults? {
    guard let suiteName = getAppGroupSuiteName() else { return nil }
    return UserDefaults(suiteName: suiteName)
}

/// Debug info for troubleshooting
private func getDebugInfo() -> String {
    let appGroup = getAppGroupSuiteName() ?? "nil"
    let hasDefaults = sharedUserDefaults != nil
    let hasData = sharedUserDefaults?.data(forKey: "complicationData") != nil
    return "AG:\(appGroup.suffix(15)) D:\(hasDefaults) V:\(hasData)"
}

// MARK: - Shared Complication Data

/// Data structure for sharing glucose information with complications
struct GlucoseComplicationData: Codable {
    let glucose: String
    let trend: String
    let delta: String
    let iob: String?
    let cob: String?
    let tdd: String?  // Total Daily Dose
    let glucoseDate: Date?
    let lastLoopDate: Date?
    let isUrgent: Bool  // true when glucose is out of range (high/low)

    static let key = "complicationData"

    // For backwards compatibility with data saved without newer fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        glucose = try container.decode(String.self, forKey: .glucose)
        trend = try container.decode(String.self, forKey: .trend)
        delta = try container.decode(String.self, forKey: .delta)
        iob = try container.decodeIfPresent(String.self, forKey: .iob)
        cob = try container.decodeIfPresent(String.self, forKey: .cob)
        tdd = try container.decodeIfPresent(String.self, forKey: .tdd)
        glucoseDate = try container.decodeIfPresent(Date.self, forKey: .glucoseDate)
        lastLoopDate = try container.decodeIfPresent(Date.self, forKey: .lastLoopDate)
        isUrgent = try container.decodeIfPresent(Bool.self, forKey: .isUrgent) ?? false
    }

    init(glucose: String, trend: String, delta: String, iob: String?, cob: String?, tdd: String? = nil, glucoseDate: Date?, lastLoopDate: Date?, isUrgent: Bool = false) {
        self.glucose = glucose
        self.trend = trend
        self.delta = delta
        self.iob = iob
        self.cob = cob
        self.tdd = tdd
        self.glucoseDate = glucoseDate
        self.lastLoopDate = lastLoopDate
        self.isUrgent = isUrgent
    }

    /// Saves the data to shared App Group UserDefaults
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            if let shared = sharedUserDefaults {
                shared.set(encoded, forKey: Self.key)
            }
            UserDefaults.standard.set(encoded, forKey: Self.key)
        }
    }

    /// Loads the data from shared App Group UserDefaults
    static func load() -> GlucoseComplicationData? {
        // Try shared App Group first (this is what the complication uses)
        if let shared = sharedUserDefaults,
           let data = shared.data(forKey: key),
           let decoded = try? JSONDecoder().decode(GlucoseComplicationData.self, from: data) {
            return decoded
        }
        // Fall back to standard UserDefaults
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(GlucoseComplicationData.self, from: data)
        else { return nil }
        return decoded
    }

    /// Returns the minutes since the last glucose reading
    var minutesAgo: Int {
        guard let glucoseDate = glucoseDate else { return 999 }
        return Int(Date().timeIntervalSince(glucoseDate) / 60)
    }

    /// Returns the time of the last glucose reading as a string (e.g., "10:45")
    var timeString: String {
        guard let glucoseDate = glucoseDate else { return "--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: glucoseDate)
    }

    /// Indicates if data is stale (> 10 min old) - shows yellow
    var isStale: Bool { minutesAgo > 10 }

    /// Indicates if data is very stale (> 15 min old) - shows value in red
    var isVeryStale: Bool { minutesAgo > 15 }

    /// Returns the appropriate color based on staleness
    var stalenessColor: Color {
        if isVeryStale { return .red }
        if isStale { return .yellow }
        return .green
    }
}

// MARK: - Timeline Entry

struct TrioWatchComplicationEntry: TimelineEntry {
    let date: Date
    let data: GlucoseComplicationData?

    static var placeholder: TrioWatchComplicationEntry {
        TrioWatchComplicationEntry(
            date: Date(),
            data: GlucoseComplicationData(
                glucose: "120",
                trend: "→",
                delta: "+2",
                iob: "1.5",
                cob: "20",
                glucoseDate: Date(),
                lastLoopDate: Date()
            )
        )
    }
}

// MARK: - Provider

struct TrioWatchComplicationProvider: TimelineProvider {
    func placeholder(in _: Context) -> TrioWatchComplicationEntry {
        .placeholder
    }

    func getSnapshot(in _: Context, completion: @escaping (TrioWatchComplicationEntry) -> Void) {
        let data = GlucoseComplicationData.load()
        let entry = TrioWatchComplicationEntry(date: Date(), data: data)
        completion(entry)
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TrioWatchComplicationEntry>) -> Void) {
        let data = GlucoseComplicationData.load()
        let currentDate = Date()

        // Create entries every 5 minutes for the next 15 minutes
        // Aligned with the 15-minute background refresh schedule
        var entries: [TrioWatchComplicationEntry] = []

        // Entry for now
        entries.append(TrioWatchComplicationEntry(date: currentDate, data: data))

        // Entries at 5, 10, and 15 minutes - matches background refresh interval
        for minutes in [5, 10, 15] {
            let futureDate = currentDate.addingTimeInterval(Double(minutes * 60))
            entries.append(TrioWatchComplicationEntry(date: futureDate, data: data))
        }

        // Use .atEnd to request refresh as soon as timeline expires
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

// MARK: - Main Entry View

struct TrioWatchComplicationEntryView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    var entry: TrioWatchComplicationEntry

    var body: some View {
        switch widgetFamily {
        case .accessoryCircular:
            AccessoryCircularView(entry: entry)
        case .accessoryCorner:
            AccessoryCornerView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularView(entry: entry)
        case .accessoryInline:
            AccessoryInlineView(entry: entry)
        default:
            // Fallback for unsupported families
            Image("ComplicationIcon")
                .widgetAccentable()
                .widgetBackground(backgroundView: Color.clear)
        }
    }
}

// MARK: - Accessory Circular View

struct AccessoryCircularView: View {
    var entry: TrioWatchComplicationEntry

    var body: some View {
        if let data = entry.data {
            ZStack {
                // Gauge showing freshness (fills as it gets stale)
                let fraction = min(Double(data.minutesAgo) / 15.0, 1.0)

                Gauge(value: 1.0 - fraction) {
                    EmptyView()
                } currentValueLabel: {
                    VStack(spacing: -2) {
                        Text(data.glucose)
                            .font(.system(size: 16, weight: .bold))
                            .minimumScaleFactor(0.6)
                        Text(data.timeString)
                            .font(.system(size: 10))
                    }
                }
                .gaugeStyle(.accessoryCircular)
                .tint(data.stalenessColor)
            }
            .widgetBackground(backgroundView: Color.clear)
        } else {
            // No data at all
            VStack(spacing: -2) {
                Text("--")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.red)
                Text("--:--")
                    .font(.system(size: 10))
            }
            .widgetBackground(backgroundView: Color.clear)
        }
    }
}

// MARK: - Accessory Corner View

struct AccessoryCornerView: View {
    var entry: TrioWatchComplicationEntry

    var body: some View {
        if let data = entry.data {
            Text(data.glucose)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(data.stalenessColor)
                .widgetCurvesContent()
                .widgetLabel {
                    if let tdd = data.tdd, !tdd.isEmpty {
                        Text("\(data.timeString) \(tdd)U")
                    } else {
                        Text(data.timeString)
                    }
                }
                .widgetBackground(backgroundView: Color.clear)
        } else {
            Text("--")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.red)
                .widgetCurvesContent()
                .widgetLabel {
                    Text("No data")
                }
                .widgetBackground(backgroundView: Color.clear)
        }
    }
}

// MARK: - Accessory Rectangular View

struct AccessoryRectangularView: View {
    var entry: TrioWatchComplicationEntry

    var body: some View {
        if let data = entry.data {
            VStack(alignment: .leading, spacing: 2) {
                // Top row: Glucose, trend, delta
                HStack {
                    Text(data.glucose)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(data.stalenessColor)
                    Text(data.trend)
                        .font(.system(size: 18))
                    Text(data.delta)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Spacer()
                }

                // Bottom row: Timestamp and TDD
                HStack(spacing: 8) {
                    Text(data.timeString)
                        .font(.system(size: 11))
                        .foregroundColor(data.stalenessColor)
                    if let tdd = data.tdd, !tdd.isEmpty {
                        Text("\(tdd)U")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .widgetBackground(backgroundView: Color.clear)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("--")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.red)
                    Text("→")
                        .font(.system(size: 18))
                    Spacer()
                }
                // Show debug info: AG=app group suffix, D=defaults exist, V=value exists
                Text(getDebugInfo())
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
            }
            .widgetBackground(backgroundView: Color.clear)
        }
    }
}

// MARK: - Accessory Inline View

struct AccessoryInlineView: View {
    var entry: TrioWatchComplicationEntry

    var body: some View {
        if let data = entry.data {
            if let tdd = data.tdd, !tdd.isEmpty {
                Text("\(data.glucose) \(data.trend) \(data.timeString) \(tdd)U")
            } else {
                Text("\(data.glucose) \(data.trend) \(data.timeString)")
            }
        } else {
            Text("Trio: no data")
        }
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
        .description("Displays live glucose, trend, and diabetes data")
        .supportedFamilies([
            .accessoryCorner,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - View Extension

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
