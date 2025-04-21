import ActivityKit
import SwiftUI
import WidgetKit

struct LiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityAttributes.self) { context in
            LiveActivityView(context: context)
        } dynamicIsland: { context in
            let hasStaticColorScheme = context.state.glucoseColorScheme == "staticColor"

            var glucoseColor: Color {
                let state = context.state
                let isMgdL = state.unit == "mg/dL"

                // TODO: workaround for now: set low value to 55, to have dynamic color shades between 55 and user-set low (approx. 70); same for high glucose
                let hardCodedLow = isMgdL ? Decimal(55) : 55.asMmolL
                let hardCodedHigh = isMgdL ? Decimal(220) : 220.asMmolL

                return Color.getDynamicGlucoseColor(
                    glucoseValue: Decimal(string: state.bg) ?? 100,
                    highGlucoseColorValue: !hasStaticColorScheme ? hardCodedHigh : state.highGlucose,
                    lowGlucoseColorValue: !hasStaticColorScheme ? hardCodedLow : state.lowGlucose,
                    targetGlucose: isMgdL ? state.target : state.target.asMmolL,
                    glucoseColorScheme: state.glucoseColorScheme
                )
            }

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveActivityExpandedLeadingView(context: context, glucoseColor: glucoseColor)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveActivityExpandedTrailingView(
                        context: context,
                        glucoseColor: hasStaticColorScheme ? .primary : glucoseColor
                    )
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LiveActivityExpandedBottomView(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    LiveActivityExpandedCenterView(context: context)
                }
            } compactLeading: {
                LiveActivityCompactLeadingView(context: context, glucoseColor: glucoseColor)
            } compactTrailing: {
                LiveActivityCompactTrailingView(context: context, glucoseColor: hasStaticColorScheme ? .primary : glucoseColor)
            } minimal: {
                LiveActivityMinimalView(context: context, glucoseColor: glucoseColor)
            }
            .widgetURL(URL(string: "Trio://"))
            .keylineTint(glucoseColor)
            .contentMargins(.horizontal, 0, for: .minimal)
            .contentMargins(.trailing, 0, for: .compactLeading)
            .contentMargins(.leading, 0, for: .compactTrailing)
        }
    }
}

// Mock structure to replace GlucoseData
struct MockGlucoseData {
    var glucose: Int
    var date: Date
    var direction: String? // You can refine this based on your expected data
}

private extension LiveActivityAttributes {
    static var preview: LiveActivityAttributes {
        LiveActivityAttributes(startDate: Date())
    }
}

private extension LiveActivityAttributes.ContentState {
    static var chartData: [MockGlucoseData] = [
        MockGlucoseData(glucose: 120, date: Date().addingTimeInterval(-600), direction: "flat"),
        MockGlucoseData(glucose: 125, date: Date().addingTimeInterval(-300), direction: "flat"),
        MockGlucoseData(glucose: 130, date: Date(), direction: "flat")
    ]

    static var detailedViewState = LiveActivityAttributes.ContentAdditionalState(
        chart: chartData.map { Decimal($0.glucose) },
        chartDate: chartData.map(\.date),
        rotationDegrees: 0,
        cob: 20,
        iob: 1.5,
        tdd: 43.21,
        isOverrideActive: false,
        overrideName: "Exercise",
        overrideDate: Date().addingTimeInterval(-3600),
        overrideDuration: 120,
        overrideTarget: 150,
        widgetItems: LiveActivityAttributes.LiveActivityItem.defaultItems
    )

    // 0 is the widest digit. Use this to get an upper bound on text width.

    // Use mmol/l notation with decimal point as well for the same reason, it uses up to 4 characters, while mg/dl uses up to 3
    static var testWide: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            unit: "mg/dL",
            bg: "00.0",
            direction: "→",
            change: "+0.0",
            date: Date(),
            highGlucose: 180,
            lowGlucose: 70,
            target: 100,
            glucoseColorScheme: "staticColor",
            detailedViewState: nil,
            isInitialState: false
        )
    }

    static var testVeryWide: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            unit: "mg/dL",
            bg: "00.0",
            direction: "↑↑",
            change: "+0.0",
            date: Date(),
            highGlucose: 180,
            lowGlucose: 70,
            target: 100,
            glucoseColorScheme: "staticColor",
            detailedViewState: nil,
            isInitialState: false
        )
    }

    static var testSuperWide: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            unit: "mg/dL",
            bg: "00.0",
            direction: "↑↑↑",
            change: "+0.0",
            date: Date(),
            highGlucose: 180,
            lowGlucose: 70,
            target: 100,
            glucoseColorScheme: "staticColor",
            detailedViewState: nil,
            isInitialState: false
        )
    }

    // 2 characters for BG, 1 character for change is the minimum that will be shown
    static var testNarrow: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            unit: "mg/dL",
            bg: "00",
            direction: "↑",
            change: "+0",
            date: Date(),
            highGlucose: 180,
            lowGlucose: 70,
            target: 100,
            glucoseColorScheme: "staticColor",
            detailedViewState: nil,
            isInitialState: false
        )
    }

    static var testMedium: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            unit: "mg/dL",
            bg: "000",
            direction: "↗︎",
            change: "+00",
            date: Date(),
            highGlucose: 180,
            lowGlucose: 70,
            target: 100,
            glucoseColorScheme: "staticColor",
            detailedViewState: nil,
            isInitialState: false
        )
    }

    static var testExpired: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            unit: "mg/dL",
            bg: "--",
            direction: nil,
            change: "--",
            date: Date().addingTimeInterval(-60 * 60),
            highGlucose: 180,
            lowGlucose: 70,
            target: 100,
            glucoseColorScheme: "staticColor",
            detailedViewState: nil,
            isInitialState: false
        )
    }

    static var testWideDetailed: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            unit: "mg/dL",
            bg: "00.0",
            direction: "→",
            change: "+0.0",
            date: Date(),
            highGlucose: 180,
            lowGlucose: 70,
            target: 100,
            glucoseColorScheme: "staticColor",
            detailedViewState: detailedViewState,
            isInitialState: false
        )
    }

    static var testVeryWideDetailed: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            unit: "mg/dL",
            bg: "00.0",
            direction: "↑↑",
            change: "+0.0",
            date: Date(),
            highGlucose: 180,
            lowGlucose: 70,
            target: 100,
            glucoseColorScheme: "staticColor",
            detailedViewState: detailedViewState,
            isInitialState: false
        )
    }

    static var testSuperWideDetailed: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            unit: "mg/dL",
            bg: "00.0",
            direction: "↑↑↑",
            change: "+0.0",
            date: Date(),
            highGlucose: 180,
            lowGlucose: 70,
            target: 100,
            glucoseColorScheme: "staticColor",
            detailedViewState: detailedViewState,
            isInitialState: false
        )
    }

    // 2 characters for BG, 1 character for change is the minimum that will be shown
    static var testNarrowDetailed: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            unit: "mg/dL",
            bg: "00",
            direction: "↑",
            change: "+0",
            date: Date(),
            highGlucose: 180,
            lowGlucose: 70,
            target: 100,
            glucoseColorScheme: "staticColor",
            detailedViewState: detailedViewState,
            isInitialState: false
        )
    }

    static var testMediumDetailed: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            unit: "mg/dL",
            bg: "000",
            direction: "↗︎",
            change: "+00",
            date: Date(),
            highGlucose: 180,
            lowGlucose: 70,
            target: 100,
            glucoseColorScheme: "staticColor",
            detailedViewState: detailedViewState,
            isInitialState: false
        )
    }

    static var testExpiredDetailed: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            unit: "mg/dL",
            bg: "--",
            direction: nil,
            change: "--",
            date: Date().addingTimeInterval(-60 * 60),
            highGlucose: 180,
            lowGlucose: 70,
            target: 100,
            glucoseColorScheme: "staticColor",
            detailedViewState: detailedViewState,
            isInitialState: false
        )
    }
}

@available(iOS 17.0, iOSApplicationExtension 17.0, *)
#Preview("Simple", as: .content, using: LiveActivityAttributes.preview) {
    LiveActivity()
} contentStates: {
    LiveActivityAttributes.ContentState.testSuperWide
    LiveActivityAttributes.ContentState.testVeryWide
    LiveActivityAttributes.ContentState.testWide
    LiveActivityAttributes.ContentState.testMedium
    LiveActivityAttributes.ContentState.testNarrow
    LiveActivityAttributes.ContentState.testExpired
}

@available(iOS 17.0, iOSApplicationExtension 17.0, *)
#Preview("Detailed", as: .content, using: LiveActivityAttributes.preview) {
    LiveActivity()
} contentStates: {
    LiveActivityAttributes.ContentState.testSuperWideDetailed
    LiveActivityAttributes.ContentState.testVeryWideDetailed
    LiveActivityAttributes.ContentState.testWideDetailed
    LiveActivityAttributes.ContentState.testMediumDetailed
    LiveActivityAttributes.ContentState.testNarrowDetailed
    LiveActivityAttributes.ContentState.testExpiredDetailed
}
