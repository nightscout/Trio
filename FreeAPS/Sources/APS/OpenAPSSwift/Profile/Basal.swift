import Foundation

struct Basal {
    static func basalLookup(_ basalProfile: [BasalProfileEntry], now: Date? = nil) throws -> Decimal? {
        let nowDate = now ?? Date()

        // Original had a sort but it was a no-op if 'i' wasn't present, so we can skip it
        let basalProfileData = basalProfile

        guard let lastBasalRate = basalProfileData.last?.rate, lastBasalRate != 0 else {
            warning(.openAPS, "Warning: bad basal schedule \(basalProfile)")
            return nil
        }

        // Look for matching time slot
        for (curr, next) in zip(basalProfileData, basalProfileData.dropFirst()) {
            if try nowDate.isMinutesFromMidnightWithinRange(lowerBound: curr.minutes, upperBound: next.minutes) {
                return curr.rate.rounded(scale: 3)
            }
        }

        // If no matching slot found, return last basal rate
        return lastBasalRate.rounded(scale: 3)
    }

    static func maxDailyBasal(_ basalProfile: [BasalProfileEntry]) -> Decimal? {
        guard let maxBasal = basalProfile.map(\.rate).max() else {
            return nil
        }

        // In Javascript Number is floating point, so we don't need to do
        // the * 1000 / 1000
        return maxBasal
    }
}
