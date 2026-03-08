import SwiftUI
import WidgetKit

struct MealScanWidget: Widget {
    let kind = "MealScanWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MealScanTimelineProvider()) { _ in
            MealScanWidgetView()
        }
        .configurationDisplayName("Scan Meal")
        .description("Quick access to photo meal scanning")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - Timeline Provider

struct MealScanTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> MealScanEntry {
        MealScanEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (MealScanEntry) -> Void) {
        completion(MealScanEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MealScanEntry>) -> Void) {
        let entry = MealScanEntry(date: Date())
        // Static widget — no updates needed
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

struct MealScanEntry: TimelineEntry {
    let date: Date
}

// MARK: - Widget View

struct MealScanWidgetView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "camera.fill")
                .font(.title2)
                .foregroundStyle(.primary)
        }
        .widgetURL(URL(string: "Trio://mealScan"))
    }
}
