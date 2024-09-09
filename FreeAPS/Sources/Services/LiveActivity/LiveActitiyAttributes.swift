import ActivityKit
import Foundation

struct LiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        let bg: String
        let direction: String?
        let change: String
        let date: Date

        let detailedViewState: ContentAdditionalState?

        let showCOB: Bool
        let showIOB: Bool
        let showCurrentGlucose: Bool
        let showUpdatedLabel: Bool

        let itemOrder: [String]

        /// true for the first state that is set on the activity
        let isInitialState: Bool
    }

    public struct ContentAdditionalState: Codable, Hashable {
        let chart: [Decimal]
        let chartDate: [Date?]
        let rotationDegrees: Double
        let highGlucose: Decimal
        let lowGlucose: Decimal
        let target: Decimal
        let cob: Decimal
        let iob: Decimal
        let unit: String
        let isOverrideActive: Bool
        let overrideName: String
    }

    let startDate: Date
}
