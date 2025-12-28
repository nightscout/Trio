import Foundation

struct IobGenerator {
    static func generate(
        history: [PumpHistoryEvent],
        profile: Profile,
        clock: Date,
        autosens: Autosens?
    ) throws -> [IobResult] {
        let pumpHistory = history.map { $0.computedEvent() }

        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory,
            profile: profile,
            clock: clock,
            autosens: autosens,
            zeroTempDuration: nil
        )
        let treatmentsWithZeroTemp = try IobHistory.calcTempTreatments(
            history: pumpHistory,
            profile: profile,
            clock: clock,
            autosens: autosens,
            zeroTempDuration: 240
        )

        // In Javascript it checks for `started_at` to separate tempBolus
        // from bolus but we explicitly track tempBolus instead
        let lastBolusTime = treatments.filter({ $0.insulin != nil && $0.isTempBolus == false && $0.insulin != 0 })
            .map(\.timestamp)
            .max() ?? Date(timeIntervalSince1970: 0)
        let lastTemp = treatments.filter({ $0.rate != nil && ($0.duration ?? 0) > 0 }).sorted(by: { $0.timestamp < $1.timestamp })
            .last

        let iStop = 4 * 60 // look 4h into the future
        var iobArray = try stride(from: 0, to: iStop, by: 5).map { minutes in
            let time = clock + minutes.minutesToSeconds
            let iob = try IobCalculation.iobTotal(treatments: treatments, profile: profile, time: time)
            let iobWithZeroTemp = try IobCalculation.iobTotal(treatments: treatmentsWithZeroTemp, profile: profile, time: time)
            return IobResult.from(iob: iob, iobWithZeroTemp: iobWithZeroTemp)
        }

        if !iobArray.isEmpty {
            iobArray[0].lastTemp = lastTemp?.toLastTemp() ?? IobResult.LastTemp()
            iobArray[0].lastBolusTime = UInt64(lastBolusTime.timeIntervalSince1970 * 1000)
        }

        return iobArray
    }
}
