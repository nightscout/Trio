import Foundation

/// Helper functions for TempTarget sensitivity calculations.
/// These are used across the app (UI, OpenAPS) to ensure consistent behavior.
enum TempTargetCalculations {
    /// The minimum allowed sensitivity ratio for TempTargets (15%)
    static let minSensitivityRatioTT: Double = 15

    /// The normal target glucose value used as reference (100 mg/dL)
    static let normalTarget: Decimal = 100

    /// Computes the adjusted percentage (clamped to minSensitivityRatioTT).
    /// - Parameters:
    ///   - halfBasalTarget: The half basal target value
    ///   - target: The target glucose value
    ///   - autosensMax: The maximum autosens multiplier from settings
    /// - Returns: The clamped percentage (minimum is minSensitivityRatioTT)
    static func computeAdjustedPercentage(
        halfBasalTarget: Decimal,
        target: Decimal,
        autosensMax: Decimal
    ) -> Double {
        let rawPercentage = computeRawPercentage(
            halfBasalTarget: halfBasalTarget,
            target: target,
            autosensMax: autosensMax
        )
        return max(rawPercentage, minSensitivityRatioTT)
    }

    /// Computes the raw (unclamped) percentage - private helper.
    private static func computeRawPercentage(
        halfBasalTarget: Decimal,
        target: Decimal,
        autosensMax: Decimal
    ) -> Double {
        let deviationFromNormal = halfBasalTarget - normalTarget
        let adjustmentFactor = deviationFromNormal + (target - normalTarget)
        let adjustmentRatio: Decimal = (deviationFromNormal * adjustmentFactor <= 0)
            ? autosensMax
            : deviationFromNormal / adjustmentFactor
        return Double(min(adjustmentRatio, autosensMax) * 100)
    }

    /// Computes the half-basal target needed to achieve a given percentage.
    /// - Parameters:
    ///   - target: The target glucose value
    ///   - percentage: The desired sensitivity percentage
    /// - Returns: The half basal target value that yields the given percentage
    static func computeHalfBasalTarget(
        target: Decimal,
        percentage: Double
    ) -> Double {
        var adjustmentPercentage = percentage
        if adjustmentPercentage < minSensitivityRatioTT {
            adjustmentPercentage = minSensitivityRatioTT
        }
        let adjustmentRatio = Decimal(adjustmentPercentage / 100)
        var halfBasalTargetValue: Decimal = 160 // default
        if adjustmentRatio != 1 {
            halfBasalTargetValue = ((2 * adjustmentRatio * normalTarget) - normalTarget - (adjustmentRatio * target)) /
                (adjustmentRatio - 1)
        }
        return round(Double(halfBasalTargetValue))
    }

    /// Determines the effective HBT to use for a TempTarget.
    /// If the stored HBT is nil (standard TT) and using settings HBT would result in <= 15%,
    /// calculates an adjusted HBT. Otherwise returns the stored HBT or nil.
    /// - Parameters:
    ///   - tempTargetHalfBasalTarget: The HBT stored with the TempTarget (nil for standard TT)
    ///   - settingHalfBasalTarget: The HBT from user settings
    ///   - target: The target glucose value
    ///   - autosensMax: The maximum autosens multiplier from settings
    /// - Returns: The effective HBT to use, or nil if settings HBT should be used as-is
    static func computeEffectiveHBT(
        tempTargetHalfBasalTarget: Decimal?,
        settingHalfBasalTarget: Decimal,
        target: Decimal,
        autosensMax: Decimal
    ) -> Decimal? {
        // If TempTarget has a stored HBT, use it directly
        if let tempTargetHalfBasalTarget {
            return tempTargetHalfBasalTarget
        }

        // For standard TT (no stored HBT), check if settings HBT would result in <= minimum
        let rawPercentage = computeRawPercentage(
            halfBasalTarget: settingHalfBasalTarget,
            target: target,
            autosensMax: autosensMax
        )

        // If raw percentage is at or below minimum, calculate an adjusted HBT
        if rawPercentage <= minSensitivityRatioTT {
            return Decimal(computeHalfBasalTarget(
                target: target,
                percentage: minSensitivityRatioTT
            ))
        }

        return nil
    }
}
