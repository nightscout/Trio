import Foundation

public struct Autosens: JSON {
    public struct DebugInfo: Codable {
        public let iobClock: Date
        public let bgi: Decimal
        public let iobActivity: Decimal
        public let deltaGlucose: Decimal
        public let deviation: Decimal
        public let stateType: String
        // COB state for debugging state transitions
        public var mealCOB: Decimal?
        public var absorbing: Bool?
        public var mealCarbs: Decimal?
        public var mealStartCounter: Int?
    }

    public let ratio: Decimal
    public let newisf: Decimal?
    public var deviationsUnsorted: [Decimal]?
    public var timestamp: Date?
    public var debugInfo: [DebugInfo]?
    public var error: String?

    public init(
        ratio: Decimal,
        newisf: Decimal? = nil,
        deviationsUnsorted: [Decimal]? = nil,
        timestamp: Date? = nil,
        debugInfo: [DebugInfo]? = nil,
        error: String? = nil
    ) {
        self.ratio = ratio
        self.newisf = newisf
        self.deviationsUnsorted = deviationsUnsorted
        self.timestamp = timestamp
        self.debugInfo = debugInfo
        self.error = error
    }
}
