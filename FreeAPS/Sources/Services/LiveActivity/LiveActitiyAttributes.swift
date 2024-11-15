import ActivityKit
import Foundation

struct LiveActivityAttributes: ActivityAttributes {
    enum LiveActivityItem: String, Hashable, Codable, Equatable {
        case currentGlucose
        case iob
        case cob
        case updatedLabel
        case empty

        static let defaultItems: [Self] = [.currentGlucose, .iob, .cob, .updatedLabel]
    }

    struct ContentState: Codable, Hashable {
        let bg: String
        let direction: String?
        let change: String
        let date: Date?
        let highGlucose: Decimal
        let lowGlucose: Decimal
        let target: Decimal
        let glucoseColorScheme: String
        let detailedViewState: ContentAdditionalState?

        /// true for the first state that is set on the activity
        let isInitialState: Bool
    }

    struct ContentAdditionalState: Codable, Hashable {
        let chart: [Decimal]
        let chartDate: [Date?]
        let rotationDegrees: Double
        let cob: Decimal
        let iob: Decimal
        let unit: String
        let isOverrideActive: Bool
        let overrideName: String
        let overrideDate: Date
        let overrideDuration: Decimal
        let overrideTarget: Decimal
        let widgetItems: [LiveActivityItem]
    }

    let startDate: Date
}
