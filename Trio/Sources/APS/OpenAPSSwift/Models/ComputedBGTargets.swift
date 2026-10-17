import Foundation

public struct ComputedBGTargetEntry: Codable {
    public var low: Decimal
    public var high: Decimal
    public var start: String
    public var offset: Int
    public var maxBg: Decimal?
    public var minBg: Decimal?
    public var temptargetSet: Bool?

    public init(
        low: Decimal,
        high: Decimal,
        start: String,
        offset: Int,
        maxBg: Decimal? = nil,
        minBg: Decimal? = nil,
        temptargetSet: Bool? = nil
    ) {
        self.low = low
        self.high = high
        self.start = start
        self.offset = offset
        self.maxBg = maxBg
        self.minBg = minBg
        self.temptargetSet = temptargetSet
    }
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

public struct ComputedBGTargets: Codable {
    public let units: GlucoseUnits
    public let userPreferredUnits: GlucoseUnits
    public var targets: [ComputedBGTargetEntry]

    public init(units: GlucoseUnits, userPreferredUnits: GlucoseUnits, targets: [ComputedBGTargetEntry]) {
        self.units = units
        self.userPreferredUnits = userPreferredUnits
        self.targets = targets
    }
}

extension ComputedBGTargets {
    private enum CodingKeys: String, CodingKey {
        case units
        case userPreferredUnits = "user_preferred_units"
        case targets
    }
}
