import Foundation

struct IobResult: Codable {
    static func from(iob: IobTotal, iobWithZeroTemp: IobTotal) -> IobResult {
        IobResult(
            iob: iob.iob,
            activity: iob.activity,
            basaliob: iob.basaliob,
            bolusiob: iob.bolusiob,
            netbasalinsulin: iob.netbasalinsulin,
            bolusinsulin: iob.bolusinsulin,
            time: iob.time,
            iobWithZeroTemp: IobWithZeroTemp(
                iob: iobWithZeroTemp.iob,
                activity: iobWithZeroTemp.activity,
                basaliob: iobWithZeroTemp.basaliob,
                bolusiob: iobWithZeroTemp.bolusiob,
                netbasalinsulin: iobWithZeroTemp.netbasalinsulin,
                bolusinsulin: iobWithZeroTemp.bolusinsulin,
                time: iobWithZeroTemp.time
            ),
            lastBolusTime: nil,
            lastTemp: nil
        )
    }

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

        init(rate: Decimal, timestamp: Date, started_at: Date, date: UInt64, duration: Decimal) {
            self.rate = rate
            self.timestamp = timestamp
            self.started_at = started_at
            self.date = date
            self.duration = duration
        }

        // this constructor helps handle the JSON output for the case when there
        // aren't any temp basals to match the output from Javascript
        init() {
            rate = nil
            timestamp = nil
            started_at = nil
            date = 0
            duration = nil
        }
    }
}

extension ComputedPumpHistoryEvent {
    func toLastTemp() -> IobResult.LastTemp? {
        // Only convert if we have the required fields and it's a temp event
        guard let rate = self.rate,
              let duration = self.duration
        else {
            return nil
        }

        return IobResult.LastTemp(
            rate: rate,
            timestamp: timestamp,
            started_at: started_at,
            date: date,
            duration: duration
        )
    }
}
