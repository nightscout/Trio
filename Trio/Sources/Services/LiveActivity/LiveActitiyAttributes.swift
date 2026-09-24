import ActivityKit
import Foundation

struct LiveActivityAttributes: ActivityAttributes {
    enum LiveActivityItem: String, Hashable, Codable, Equatable {
        case currentGlucoseLarge
        /// Glucose and trend, no delta, in the default text color rather than the glucose color.
        case currentGlucoseLargeUncolored
        case currentGlucose
        /// Glucose, trend and delta with the reading in the glucose color.
        case currentGlucoseColored
        /// Glucose, trend arrow and delta on a single line. Occupies two of the four configuration slots.
        case currentGlucoseWide
        /// Double-width glucose, trend and delta in the default text color rather than the glucose color.
        case currentGlucoseWideUncolored
        case iob
        case cob
        case updatedLabel
        case totalDailyDose
        case empty
        /// Holds the second slot of the preceding double-width item. Renders nothing.
        case wideContinuation

        static let defaultItems: [Self] = [.currentGlucoseLarge, .iob, .cob, .updatedLabel]
    }

    /// Appearance of the glucose reading in the Simple Lock Screen layout.
    ///
    /// Mirrors the user's choices on the Simple style's Widget Configuration screen. The Detailed layout is
    /// configured through `ContentAdditionalState.widgetItems` instead.
    struct SimpleViewStyle: Codable, Hashable {
        let fontSize: LiveActivityFontSize

        /// Appearance used where no settings are available, such as SwiftUI previews.
        static let `default` = SimpleViewStyle(fontSize: .large)
    }

    struct ContentState: Codable, Hashable {
        let unit: String
        let bg: String
        let direction: String?
        let change: String
        let date: Date?
        let highGlucose: Decimal
        let lowGlucose: Decimal
        let target: Decimal
        let glucoseColorScheme: String
        let useDetailedViewIOS: Bool
        let useDetailedViewWatchOS: Bool
        let simpleViewStyle: SimpleViewStyle
        let detailedViewState: ContentAdditionalState

        /// true for the first state that is set on the activity
        let isInitialState: Bool
    }

    struct ContentAdditionalState: Codable, Hashable {
        let chart: [ChartItem]
        let rotationDegrees: Double
        let cob: Decimal
        let iob: Decimal
        let tdd: Decimal
        let isOverrideActive: Bool
        let overrideName: String
        let overrideDate: Date
        let overrideDuration: Decimal
        let overrideTarget: Decimal
        let isTempTargetActive: Bool
        let tempTargetName: String
        let tempTargetDate: Date
        let tempTargetDuration: Decimal
        let tempTargetTarget: Decimal
        let widgetItems: [LiveActivityItem]
        let minForecast: [Int]
        let maxForecast: [Int]
        let forecastLines: [ForecastLine]
        let forecastDisplayType: String
    }

    struct ChartItem: Codable, Hashable {
        let value: Decimal
        let date: Date
    }

    struct ForecastLine: Codable, Hashable {
        let type: String
        let values: [Int]
    }

    let startDate: Date
}
