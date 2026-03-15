import Foundation

struct IOBEntry: JSON {
    let iob: Decimal
    let activity: Decimal
    let basaliob: Decimal
    let bolusiob: Decimal
    let netbasalinsulin: Decimal
    let bolusinsulin: Decimal
    let iobWithZeroTemp: WithZeroTemp?
    let lastBolusTime: UInt64?
    let lastTemp: LastTemp?
    var time: Date?

    struct WithZeroTemp: JSON {
        let iob: Decimal
        let activity: Decimal
        let basaliob: Decimal
        let bolusiob: Decimal
        let netbasalinsulin: Decimal
        let bolusinsulin: Decimal
        let time: Date
    }

    struct LastTemp: JSON {
        let rate: Decimal
        let timestamp: Date
        let started_at: Date
        let date: UInt64
        let duration: Decimal
    }
}
