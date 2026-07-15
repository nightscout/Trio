import Foundation
import LoopKit

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
        let activityContrib: Double
        let iobContrib: Double
    }

    /// Effective insulinPeakTime in minutes, taking into account `useCustomPeakTime`.
    /// Defaults come from LoopKit's exponential presets, custom values are clamped
    /// to oref0's bounds. Bilinear has no exponential peak and yields nil.
    static func lookupPeak(curve: InsulinCurve, useCustomPeakTime: Bool, insulinPeakTime: Decimal) -> Double? {
        let model: ExponentialInsulinModelPreset
        let customBounds: ClosedRange<Double>
        switch curve {
        case .rapidActing:
            model = .rapidActingAdult
            customBounds = 50 ... 120
        case .ultraRapid:
            model = .fiasp
            customBounds = 35 ... 100
        case .bilinear:
            return nil
        }
        guard useCustomPeakTime else { return model.peakActivity / 60 }
        return Double(insulinPeakTime).clamp(lowerBound: customBounds.lowerBound, upperBound: customBounds.upperBound)
    }

    /// Runs through the IoB calculation for a treatment.
    ///
    /// **IMPORTANT** this calculation uses Doubles internally for performance
    static func iobCalc(
        treatment: ComputedPumpHistoryEvent,
        time: Date,
        dia: Decimal,
        profile: Profile
    ) throws -> IobCalculationResult? {
        guard let insulin = treatment.insulin.map({ Double($0) }) else {
            return nil
        }

        let bolusTime = treatment.timestamp
        let minsAgo = (time.timeIntervalSince(bolusTime) / 60.0).rounded()
        guard let peak = lookupPeak(
            curve: profile.curve,
            useCustomPeakTime: profile.useCustomPeakTime,
            insulinPeakTime: profile.insulinPeakTime
        ) else {
            throw IobError.bilinearCurveNotSupported
        }
        let end = Double(dia) * 60

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

        guard activityContrib.isFinite, iobContrib.isFinite else {
            return IobCalculationResult(activityContrib: 0, iobContrib: 0)
        }

        return IobCalculationResult(activityContrib: activityContrib, iobContrib: iobContrib)
    }

    /// Round a Double using the same logic as Decimal.jsRounded(scale:):
    /// floor(value * 10^scale + 0.5) / 10^scale
    private static func jsRound(_ value: Double, scale: Int) -> Decimal {
        guard value.isFinite else { return 0 }
        let multiplier = pow(10.0, Double(scale))
        return Decimal((value * multiplier + 0.5).rounded(.down) / multiplier)
    }

    static func iobTotal(treatments: [ComputedPumpHistoryEvent], profile: Profile, time now: Date) throws -> IobTotal {
        guard var dia = profile.dia else {
            throw IobError.diaNotSet
        }

        var iob = 0.0
        var basaliob = 0.0
        var bolusiob = 0.0
        var netbasalinsulin = 0.0
        var bolusinsulin = 0.0
        var activity = 0.0

        if dia < 5 {
            dia = 5
        }

        let diaAgo = now - Double(dia * 60 * 60) // convert to seconds
        let treatments = treatments.filter({ $0.timestamp <= now && $0.timestamp > diaAgo })
        for treatment in treatments {
            guard let tIOB = try iobCalc(treatment: treatment, time: now, dia: dia, profile: profile),
                  let insulin = treatment.insulin.map({ Double($0) })
            else {
                continue
            }
            iob += tIOB.iobContrib
            activity += tIOB.activityContrib
            if tIOB.iobContrib != 0 {
                if insulin < 0.1 {
                    // bolus to represent temp basal, which can only be 0.05 or -0.05
                    basaliob += tIOB.iobContrib
                    netbasalinsulin += insulin
                } else {
                    bolusiob += tIOB.iobContrib
                    bolusinsulin += insulin
                }
            }
        }

        return IobTotal(
            iob: jsRound(iob, scale: 3),
            activity: jsRound(activity, scale: 4),
            basaliob: jsRound(basaliob, scale: 3),
            bolusiob: jsRound(bolusiob, scale: 3),
            netbasalinsulin: jsRound(netbasalinsulin, scale: 3),
            bolusinsulin: jsRound(bolusinsulin, scale: 3),
            time: now
        )
    }
}
