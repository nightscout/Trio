import Foundation

struct WatchState: Codable {
    var glucose: String?
    var trend: String?
    var trendRaw: String?
    var delta: String?
    var glucoseDate: Date?
    var lastLoopDate: Date?
    var lastLoopDateInterval: UInt64?
    var bolusIncrement: Decimal?
    var maxCOB: Decimal?
    var maxBolus: Decimal?
    var carbsRequired: Decimal?
    var bolusRecommended: Decimal?
    var iob: Decimal?
    var cob: Decimal?
    var tempTargets: [TempTargetWatchPreset] = []
    var bolusAfterCarbs: Bool?
    var eventualBG: String?
    var eventualBGRaw: String?
    var displayOnWatch: AwConfig?
    var displayFatAndProteinOnWatch: Bool?
    var confirmBolusFaster: Bool?
<<<<<<< HEAD
    var useNewCalc: Bool?
=======
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
    var isf: Decimal?
    var override: String?
}

struct TempTargetWatchPreset: Codable, Identifiable {
    let name: String
    let id: String
    let description: String
    let until: Date?
}
