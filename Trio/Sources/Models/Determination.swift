import Foundation

struct Determination: JSON, Equatable {
    let id: UUID?
    var reason: String
    let units: Decimal?
    let insulinReq: Decimal?
    var eventualBG: Int?
    let sensitivityRatio: Decimal?
    let rate: Decimal?
    let duration: Decimal?
    let iob: Decimal?
    let cob: Decimal?
    var predictions: Predictions?
    var deliverAt: Date?
    let carbsReq: Decimal?
    let temp: TempType?
    var bg: Decimal?
    let reservoir: Decimal?
    var isf: Decimal?
    var timestamp: Date?

    /// `tdd` (Total Daily Dose) is included so it can be part of the
    /// enacted and suggested devicestatus data that gets uploaded to Nightscout.
    var tdd: Decimal?

    var current_target: Decimal?
    let insulinForManualBolus: Decimal?
    let manualBolusErrorString: Decimal?
    var minDelta: Decimal?
    var expectedDelta: Decimal?
    var minGuardBG: Decimal?
    var minPredBG: Decimal?
    var threshold: Decimal?
    let carbRatio: Decimal?
    let received: Bool?
}

struct Predictions: JSON, Equatable {
    let iob: [Int]?
    let zt: [Int]?
    let cob: [Int]?
    let uam: [Int]?
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
        case insulinForManualBolus
        case manualBolusErrorString
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
