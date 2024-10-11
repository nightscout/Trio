import ActivityKit
import Foundation

struct LiveActivityAttributes: ActivityAttributes {
    enum ItemOrder: String, Hashable, Codable, Equatable {
        case currentGlucose
        case iob
        case cob
        case updatedLabel
        case empty
    }

    struct ContentState: Codable, Hashable {
        let bg: String
        let direction: String?
        let change: String
        let date: Date
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
        let itemOrder: [ItemOrder]
        let showCOB: Bool
        let showIOB: Bool
        let showCurrentGlucose: Bool
        let showUpdatedLabel: Bool
    }

    let startDate: Date
}

extension LiveActivityAttributes.ItemOrder {
    static let defaultOrders: [Self] = [.currentGlucose, .iob, .cob, .updatedLabel]
}
