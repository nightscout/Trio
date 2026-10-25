import Foundation

public struct Determination: JSON, Equatable {
    public let id: UUID?
    public var reason: String
    public var units: Decimal?
    public var insulinReq: Decimal?
    public var eventualBG: Int?
    public let sensitivityRatio: Decimal?
    public var rate: Decimal?
    public var duration: Decimal?
    public let iob: Decimal?
    public let cob: Decimal?
    public var predictions: Predictions?
    public var deliverAt: Date?
    public let carbsReq: Decimal?
    public let temp: TempType?
    public var bg: Decimal?
    public let reservoir: Decimal?
    public var isf: Decimal?
    public var timestamp: Date?

    /// `tdd` (Total Daily Dose) is included so it can be part of the
    /// enacted and suggested devicestatus data that gets uploaded to Nightscout.
    public var tdd: Decimal?

    public var current_target: Decimal?
    public var minDelta: Decimal?
    public var expectedDelta: Decimal?
    public var minGuardBG: Decimal?
    public var minPredBG: Decimal?
    public var threshold: Decimal?
    public let carbRatio: Decimal?
    public let received: Bool?

    /// Remaining COB per 5 min forecast step; display-only,
    /// not part of CodingKeys so the serialized JSON is unchanged.
    public var cobProjection: [Decimal]? = nil
}

public struct Predictions: JSON, Equatable {
    public let iob: [Int]?
    public let zt: [Int]?
    public let cob: [Int]?
    public let uam: [Int]?
}

extension Determination {
    private enum CodingKeys: String, CodingKey {
        case id
        case reason
        case units
        case insulinReq
        case eventualBG
        case sensitivityRatio
        case rate
        case duration
        case iob = "IOB"
        case cob = "COB"
        case predictions = "predBGs"
        case deliverAt
        case carbsReq
        case temp
        case bg
        case reservoir
        case timestamp
        case isf = "ISF"
        case current_target
        case tdd = "TDD"
        case minDelta
        case expectedDelta
        case minGuardBG
        case minPredBG
        case threshold
        case carbRatio = "CR"
        case received
    }
}

extension Predictions {
    private enum CodingKeys: String, CodingKey {
        case iob = "IOB"
        case zt = "ZT"
        case cob = "COB"
        case uam = "UAM"
    }
}

protocol DeterminationObserver {
    func determinationDidUpdate(_ determination: Determination)
}

extension Determination {
    var reasonParts: [String] {
        reason.components(separatedBy: "; ").first?.components(separatedBy: ", ") ?? []
    }

    var reasonConclusion: String {
        reason.components(separatedBy: "; ").last ?? ""
    }
}
