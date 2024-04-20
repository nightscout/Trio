import Foundation

struct Determination: JSON, Equatable {
    let reason: String
    let units: Decimal?
    let insulinReq: Decimal?
    let eventualBG: Int?
    let sensitivityRatio: Decimal?
    let rate: Decimal?
    let duration: Int?
    let iob: Decimal?
    let cob: Decimal?
    var predictions: Predictions?
    let deliverAt: Date?
    let carbsReq: Decimal?
    let temp: TempType?
    let bg: Decimal?
    let reservoir: Decimal?
    let isf: Decimal?
    var timestamp: Date?
    var recieved: Bool?
    let tdd: Decimal?
    let insulin: Insulin?
    let current_target: Decimal?
    let insulinForManualBolus: Decimal?
    let manualBolusErrorString: Decimal?
    let minDelta: Decimal?
    let expectedDelta: Decimal?
    let minGuardBG: Decimal?
    let minPredBG: Decimal?
    let threshold: Decimal?
    let carbRatio: Decimal?
}

extension Determination {
    private enum CodingKeys: String, CodingKey {
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
        case recieved
        case isf = "ISF"
        case tdd = "TDD"
        case insulin
        case current_target
        case insulinForManualBolus
        case manualBolusErrorString
        case minDelta
        case expectedDelta
        case minGuardBG
        case minPredBG
        case threshold
        case carbRatio = "CR"
    }
}

protocol DeterminationObserver {
    func determinationDidUpdate(_ determination: Determination)
}

// needed?
protocol EnactedDeterminationObserver {
    func enactedDeterminationDidUpdate(_ determination: Determination)
}

extension Determination {
    var reasonParts: [String] {
        reason.components(separatedBy: "; ").first?.components(separatedBy: ", ") ?? []
    }

    var reasonConclusion: String {
        reason.components(separatedBy: "; ").last ?? ""
    }
}
