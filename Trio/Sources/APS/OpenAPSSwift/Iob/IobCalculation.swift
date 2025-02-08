import Foundation

struct IobTotal: Codable {
    let iob: Decimal
    let activity: Decimal
    let basaliob: Decimal
    let bolusiob: Decimal
    let netbasalinsulin: Decimal
    let bolusinsulin: Decimal
    let time: Date
}

enum IobCalculation {
    struct IobCalculationResult {
        let activityContrib: Decimal
        let iobContrib: Decimal
    }

    private static func lookupPeak(from profile: Profile) throws -> Decimal {
        switch (profile.curve, profile.useCustomPeakTime, profile.insulinPeakTime) {
        case (.rapidActing, true, let insulinPeakTime):
            return insulinPeakTime.clamp(lowerBound: 50, upperBound: 120)
        case (.rapidActing, false, _):
            return 75
        case (.ultraRapid, true, let insulinPeakTime):
            return insulinPeakTime.clamp(lowerBound: 35, upperBound: 100)
        case (.ultraRapid, false, _):
            return 55
        case (.bilinear, _, _):
            throw IobError.bilinearCurveNotSupported
        }
    }

    private static func exp(_ x: Decimal) -> Decimal {
        // Convert Decimal to Double, calculate exp, convert back to Decimal
        let doubleX = NSDecimalNumber(decimal: x).doubleValue
        return Decimal(Darwin.exp(doubleX))
    }

    static func iobCalc(
        treatment: ComputedPumpHistoryEvent,
        time: Date,
        dia: Decimal,
        profile: Profile
    ) throws -> IobCalculationResult? {
        guard let insulin = treatment.insulin else {
            return nil
        }

        let bolusTime = treatment.timestamp
        let minsAgo = time.timeIntervalSince(bolusTime).secondsToMinutes.rounded()
        let peak = try lookupPeak(from: profile)
        let end = dia * Decimal(60)

        guard minsAgo < end else {
            return IobCalculationResult(activityContrib: 0, iobContrib: 0)
        }

        // Calculate the constants exactly as in JavaScript
        let tau = peak * (1 - peak / end) / (1 - 2 * peak / end)
        let a = 2 * tau / end
        let S = 1 / (1 - a + (1 + a) * exp(-end / tau))

        let activityContrib = insulin * (S / pow(tau, 2)) * minsAgo * (1 - minsAgo / end) * exp(-minsAgo / tau)
        let iobContrib = insulin *
            (1 - S * (1 - a) * ((pow(minsAgo, 2) / (tau * end * (1 - a)) - minsAgo / tau - 1) * exp(-minsAgo / tau) + 1))

        return IobCalculationResult(activityContrib: activityContrib, iobContrib: iobContrib)
    }

    static func iobTotal(treatments: [ComputedPumpHistoryEvent], profile: Profile, time now: Date) throws -> IobTotal {
        guard var dia = profile.dia else {
            throw IobError.diaNotSet
        }

        var iob = Decimal(0)
        var basaliob = Decimal(0)
        var bolusiob = Decimal(0)
        var netbasalinsulin = Decimal(0)
        var bolusinsulin = Decimal(0)
        var activity = Decimal(0)

        if dia < 5 {
            dia = 5
        }

        let diaAgo = now - Double(dia * 60 * 60) // convert to seconds
        let treatments = treatments.filter({ $0.timestamp <= now && $0.timestamp > diaAgo })
        for treatment in treatments {
            guard let tIOB = try iobCalc(treatment: treatment, time: now, dia: dia, profile: profile),
                  let insulin = treatment.insulin
            else {
                continue
            }
            iob += tIOB.iobContrib
            activity += tIOB.activityContrib
            if insulin < 0.1 {
                // bolus to represent temp basal, which can only be 0.05 or -0.05
                basaliob += tIOB.iobContrib
                netbasalinsulin += insulin
            } else {
                bolusiob += tIOB.iobContrib
                bolusinsulin += insulin
            }
        }

        return IobTotal(
            iob: iob.rounded(scale: 3),
            activity: activity.rounded(scale: 4),
            basaliob: basaliob.rounded(scale: 3),
            bolusiob: bolusiob.rounded(scale: 3),
            netbasalinsulin: netbasalinsulin.rounded(scale: 3),
            bolusinsulin: bolusinsulin.rounded(scale: 3),
            time: now
        )
    }
}
