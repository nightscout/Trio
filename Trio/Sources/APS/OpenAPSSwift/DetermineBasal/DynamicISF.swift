import Foundation

/// Represents the successful output of a dynamic ISF calculation.
struct DynamicISFResult {
    /// The final sensitivity ratio, after all calculations and clamping.
    let ratio: Decimal
    /// The ratio of 24h TDD to the 14-day average TDD, clamped by autosens limits.
    let tddRatio: Decimal
    /// The calculated insulin factor (120 - peak time), used in the logarithmic formula.
    let insulinFactor: Decimal
    /// The ratio before clamping was applied.
    let uncappedRatio: Decimal
    /// The limit value if the ratio was clamped, nil otherwise.
    let limitValue: Decimal?
}

enum DynamicISF {
    /// Calculates the dynamic ISF ratio and related values.
    ///
    /// This function ports the core logic from `determine-basal.js` for dynamic ISF.
    /// - Parameters:
    ///   - profile: The user's profile, containing settings like autosens limits and insulin curve type.
    ///   - preferences: The user's preferences, containing feature flags like `useNewFormula` and `sigmoid`.
    ///   - currentGlucose: The most recent glucose reading.
    ///   - tdd: The total daily dose of insulin, used as a key input for the logarithmic formula.
    ///   - profileTarget: The effective, override-adjusted blood glucose target. Used in the sigmoid formula.
    ///   - sensitivity: The effective, override-adjusted insulin sensitivity (ISF). Used in the logarithmic formula.
    ///   - trioCustomOrefVariables: Custom variables containing TDD averages needed for the TDD ratio calculation.
    /// - Returns: A `DynamicISFResult` struct on success, or `nil` if the feature is disabled or preconditions are not met.
    static func calculate(
        profile: Profile,
        preferences: Preferences,
        currentGlucose: Decimal,
        trioCustomOrefVariables: TrioCustomOrefVariables
    ) -> DynamicISFResult? {
        let tdd = trioCustomOrefVariables.tdd(profile: profile)

        guard preferences.useNewFormula, tdd > 0, var sensitivity = profile.sens,
              let profileTarget = profile.profileTarget(trioCustomOrefVariables: trioCustomOrefVariables)
        else {
            return nil
        }

        sensitivity = trioCustomOrefVariables.override(sensitivity: sensitivity)

        let minLimit = min(profile.autosensMin, profile.autosensMax)
        let maxLimit = max(profile.autosensMin, profile.autosensMax)

        // If the limits are invalid, disable dynamicISF
        guard maxLimit > minLimit, maxLimit >= 1, minLimit <= 1 else {
            return nil
        }

        guard preferences.dynamicIsfState(profile: profile, trioCustomOrefVariables: trioCustomOrefVariables) != .off else {
            return nil
        }

        let bg = currentGlucose

        var tdd24h_14d_Ratio: Decimal
        if trioCustomOrefVariables.average_total_data > 0 {
            tdd24h_14d_Ratio = trioCustomOrefVariables.weightedAverage / trioCustomOrefVariables.average_total_data
        } else {
            tdd24h_14d_Ratio = 1
        }

        let clampedTddRatio = tdd24h_14d_Ratio.clamp(lowerBound: minLimit, upperBound: maxLimit).rounded(scale: 2)

        let insulinFactor: Decimal
        if preferences.useCustomPeakTime {
            insulinFactor = 120 - profile.insulinPeakTime
        } else {
            switch profile.curve {
            case .rapidActing: insulinFactor = 120 - 65
            case .ultraRapid: insulinFactor = 120 - 50
            default: insulinFactor = 120 - 65
            }
        }

        var newRatio: Decimal
        if preferences.sigmoid {
            let autosensInterval = maxLimit - minLimit
            let bgDev = (bg - profileTarget) * 0.0555
            let tddFactor = clampedTddRatio
            var maxMinusOne = maxLimit - 1
            // BUG: Note this fudge factor is to avoid a divide by zero but produces
            // unintuitive (and incorrect) results. See the unit tests for an example
            if maxLimit == 1 { maxMinusOne = maxLimit + 0.01 - 1 }
            let fixOffset = Decimal.log10(1 / maxMinusOne - minLimit / maxMinusOne) / Decimal(Foundation.log10(M_E))
            let exponent = bgDev * preferences.adjustmentFactorSigmoid * tddFactor + fixOffset
            newRatio = autosensInterval / (1 + Decimal.exp(-exponent)) + minLimit
        } else {
            newRatio = sensitivity * preferences.adjustmentFactor * tdd * (Decimal.log((bg / insulinFactor) + 1) / 1800)
        }

        let clampedRatio = newRatio.clamp(lowerBound: minLimit, upperBound: maxLimit)
        let limitValue: Decimal? = if newRatio > maxLimit {
            maxLimit
        } else if newRatio < minLimit {
            minLimit
        } else {
            nil
        }

        return DynamicISFResult(
            ratio: clampedRatio,
            tddRatio: clampedTddRatio,
            insulinFactor: insulinFactor,
            uncappedRatio: newRatio,
            limitValue: limitValue
        )
    }
}

extension Decimal {
    static func exp(_ x: Decimal) -> Decimal {
        Decimal(Foundation.exp(Double(x)))
    }

    static func log10(_ x: Decimal) -> Decimal {
        Decimal(Foundation.log10(Double(x)))
    }

    static func log(_ x: Decimal) -> Decimal {
        Decimal(Foundation.log(Double(x)))
    }
}

extension TrioCustomOrefVariables {
    func tdd(profile: Profile) -> Decimal {
        if profile.weightPercentage < 1, weightedAverage > 1 {
            return weightedAverage
        } else {
            return currentTDD
        }
    }
}

enum DynamicIsfState {
    case off
    case sigmoid
    case logrithmic
}

extension Preferences {
    func dynamicIsfState(profile: Profile, trioCustomOrefVariables: TrioCustomOrefVariables) -> DynamicIsfState {
        guard useNewFormula else { return .off }

        // Turn off when autosens.min = autosens.max
        // BUG: This check matches the JS logic but there should
        // be a check for max > min. It's impossible in the UI to have
        // min > max so I'll leave it out (and we do a proper check
        // elsewhere in DynamicISF)
        let minLimit = min(profile.autosensMax, profile.autosensMin)
        let maxLimit = max(profile.autosensMax, profile.autosensMin)
        if maxLimit == minLimit || minLimit > 1 || maxLimit < 1 {
            return .off
        }

        // checks for 'exercise mode' like conditions
        if profile.highTemptargetRaisesSensitivity,
           let profileTarget = profile.profileTarget(trioCustomOrefVariables: trioCustomOrefVariables), profileTarget >= 118
        {
            return .off
        }

        return sigmoid ? .sigmoid : .logrithmic
    }
}
