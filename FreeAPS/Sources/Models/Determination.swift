import Foundation

struct Determination: JSON, Equatable {
    let id: UUID?
    let reason: String
    let units: Decimal?
    let insulinReq: Decimal?
    let eventualBG: Int?
    let sensitivityRatio: Decimal?
    let rate: Decimal?
    let duration: Decimal?
    let iob: Decimal?
    let cob: Decimal?
    var predictions: Predictions?
    var deliverAt: Date?
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

struct Predictions: JSON, Equatable {
    let iob: [Int]?
    let zt: [Int]?
    let cob: [Int]?
    let uam: [Int]?
}

struct Insulin: JSON, Equatable {
    let TDD: Decimal?
    let bolus: Decimal?
    let temp_basal: Decimal?
    let scheduled_basal: Decimal?
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

extension Predictions {
    private enum CodingKeys: String, CodingKey {
        case iob = "IOB"
        case zt = "ZT"
        case cob = "COB"
        case uam = "UAM"
    }
}

extension Insulin {
    private enum CodingKeys: String, CodingKey {
        case TDD
        case bolus
        case temp_basal
        case scheduled_basal
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
