import Foundation

/// A model to represent IoB results returned from the oref `iob` call via JSON
struct IobResult: Codable {
    let iob: Decimal
    let activity: Decimal
    let basaliob: Decimal
    let bolusiob: Decimal
    let netbasalinsulin: Decimal
    let bolusinsulin: Decimal
    let time: Date
    let iobWithZeroTemp: IobWithZeroTemp
    var lastBolusTime: UInt64?
    var lastTemp: LastTemp?

    struct IobWithZeroTemp: Codable {
        let iob: Decimal
        let activity: Decimal
        let basaliob: Decimal
        let bolusiob: Decimal
        let netbasalinsulin: Decimal
        let bolusinsulin: Decimal
        let time: Date
    }

    struct LastTemp: Codable {
        let rate: Decimal?
        let timestamp: Date?
        let started_at: Date?
        let date: UInt64
        let duration: Decimal?
    }
}
