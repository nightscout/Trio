import Foundation

enum TempBasalFunctionError: LocalizedError, Equatable {
    case invalidMaxDailySafetyMultiplier
    case invalidCurrentBasalSafetyMultiplier
    case invalidBasalRateOnProfile

    var errorDescription: String? {
        switch self {
        case .invalidMaxDailySafetyMultiplier:
            return "The max daily safety multiplier set on Profile is invalid"
        case .invalidCurrentBasalSafetyMultiplier:
            return "The current daily basal safety multiplier set on Profile is invalid"
        case .invalidBasalRateOnProfile:
            return "The max currentBasal, maxBasal, or maxDailyBasl wasn't set on Profile"
        }
    }
}

enum TempBasalFunctions {
    /// Rounds basal rates to match the basal increment for the pump as the basal rate increases
    static func roundBasal(profile: Profile, basalRate: Decimal) -> Decimal {
        // FIXME: Should we just call the pumpManager here?

        let lowestRateScale: Decimal
        if let model = profile.model, model.hasSuffix("54") || model.hasSuffix("23") {
            lowestRateScale = 40
        } else {
            lowestRateScale = 20
        }

        let roundedBasal: Decimal
        if basalRate < 1 {
            roundedBasal = (basalRate * lowestRateScale).jsRounded() / lowestRateScale
        } else if basalRate < 10 {
            roundedBasal = (basalRate * 20).jsRounded() / 20
        } else {
            roundedBasal = (basalRate * 10).jsRounded() / 10
        }

        return roundedBasal
    }

    /// defines the max safe basal rate given a profile
    static func getMaxSafeBasalRate(profile: Profile) throws -> Decimal {
        guard !profile.maxDailySafetyMultiplier.isNaN else {
            throw TempBasalFunctionError.invalidMaxDailySafetyMultiplier
        }

        guard !profile.currentBasalSafetyMultiplier.isNaN else {
            throw TempBasalFunctionError.invalidCurrentBasalSafetyMultiplier
        }

        guard let currentBasal = profile.currentBasal, let maxDailyBasal = profile.maxDailyBasal,
              let maxBasal = profile.maxBasal
        else {
            throw TempBasalFunctionError.invalidBasalRateOnProfile
        }

        return min(
            maxBasal,
            profile.maxDailySafetyMultiplier * maxDailyBasal,
            profile.currentBasalSafetyMultiplier * currentBasal
        )
    }
}
