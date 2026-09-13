import Foundation

struct Basal {
    /// Precomputed schedule for repeated lookups; selection mirrors `basalLookup` exactly
    struct PreparedSchedule {
        private let basalProfile: [BasalProfileEntry]
        private let roundedRates: [Decimal]
        private let lastRateIsValid: Bool

        init(_ basalProfile: [BasalProfileEntry]) {
            self.basalProfile = basalProfile
            roundedRates = basalProfile.map { $0.rate.rounded(scale: 3) }
            lastRateIsValid = (basalProfile.last?.rate ?? 0) != 0
        }

        func rate(at timestamp: Date) throws -> Decimal? {
            guard lastRateIsValid else {
                warning(.openAPS, "Warning: bad basal schedule \(basalProfile)")
                return nil
            }
            guard basalProfile.count > 1 else {
                return roundedRates.last
            }
            guard let minutes = timestamp.minutesSinceMidnight else {
                throw CalendarError.invalidCalendar
            }
            for (index, pair) in zip(basalProfile, basalProfile.dropFirst()).enumerated()
                where minutes >= pair.0.minutes && minutes < pair.1.minutes
            {
                return roundedRates[index]
            }
            return roundedRates.last
        }
    }

    static func basalLookup(_ basalProfile: [BasalProfileEntry], now: Date) throws -> Decimal? {
        let nowDate = now

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
