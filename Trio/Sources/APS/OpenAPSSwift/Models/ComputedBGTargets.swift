import Foundation

struct ComputedBGTargetEntry: Codable {
    var low: Decimal
    var high: Decimal
    var start: String
    var offset: Int
    var maxBg: Decimal?
    var minBg: Decimal?
    var temptargetSet: Bool?
}

extension ComputedBGTargetEntry {
    private enum CodingKeys: String, CodingKey {
        case low
        case high
        case start
        case offset
        case maxBg = "max_bg"
        case minBg = "min_bg"
        case temptargetSet
    }
}

struct ComputedBGTargets: Codable {
    let units: GlucoseUnits
    let userPreferredUnits: GlucoseUnits
    var targets: [ComputedBGTargetEntry]
}

extension ComputedBGTargets {
    private enum CodingKeys: String, CodingKey {
        case units
        case userPreferredUnits = "user_preferred_units"
        case targets
    }
}
