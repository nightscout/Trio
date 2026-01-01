import Foundation

struct Autosens: JSON {
    struct DebugInfo: Codable {
        let iobClock: Date
        let bgi: Decimal
        let iobActivity: Decimal
        let deltaGlucose: Decimal
        let deviation: Decimal
        let stateType: String
        // COB state for debugging state transitions
        var mealCOB: Decimal?
        var absorbing: Bool?
        var mealCarbs: Decimal?
        var mealStartCounter: Int?
    }

    let ratio: Decimal
    let newisf: Decimal?
    var deviationsUnsorted: [Decimal]?
    var timestamp: Date?
    var debugInfo: [DebugInfo]?
    var error: String?
}
