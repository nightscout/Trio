import Foundation

struct IobGenerator {
    static func generate(
        history: [PumpHistoryEvent],
        profile: Profile,
        clock: Date,
        autosens: Autosens?
    ) throws -> [IobResult] {
        // As a performance optimization, filter out any pump events
        // that occurred before the DIA would use it
        let durationOfInsulinActionAgo = Double(profile.dia ?? 10) * 60 * 60
        // add an extra two hours to the DIA to ensure we get all temp basals
        let lastDurationOfInsulinAction = clock - durationOfInsulinActionAgo - 2.hoursToSeconds

        // we have to keep all of our suspend/resume events due to a hardcoded
        // DIA value in dealing with suspended pumps in JS
        var pumpHistory = history.filter({ $0.timestamp >= lastDurationOfInsulinAction || $0.isSuspendOrResume() })
            .map({ $0.computedEvent() })

        // To make sure that lastTemp and lastBolusTime are filled in
        // correctly, we need to check if there aren't any tempBasal or bolus
        // events in the DIA-filtered list. If not, find the most recent one
        // from the full history and add it.
        if pumpHistory.filter({ $0.type == .tempBasal }).isEmpty {
            // Find the most recent TempBasal event from before the DIA cutoff
            let olderTempBasals = history.filter({ $0.type == .tempBasal && $0.timestamp < lastDurationOfInsulinAction })
            if let lastTempBasal = olderTempBasals.max(by: { $0.timestamp < $1.timestamp }) {
                // Find its matching TempBasalDuration (same timestamp)
                if let matchingDuration = history
                    .first(where: { $0.type == .tempBasalDuration && $0.timestamp == lastTempBasal.timestamp })
                {
                    pumpHistory.append(lastTempBasal.computedEvent())
                    pumpHistory.append(matchingDuration.computedEvent())
                }
            }
        }

        // we need to check for amount != 0 to match the lastBolusTime logic
        if pumpHistory.filter({ $0.type == .bolus && $0.amount != 0 }).isEmpty {
            // Find the most recent Bolus event from before the DIA cutoff
            let olderBoluses = history
                .filter({ $0.type == .bolus && $0.amount != 0 && $0.timestamp < lastDurationOfInsulinAction })
            if let lastBolus = olderBoluses.max(by: { $0.timestamp < $1.timestamp }) {
                pumpHistory.append(lastBolus.computedEvent())
            }
        }

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
