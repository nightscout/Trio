import Foundation

/// A point-in-time snapshot of all Garmin health data relevant to insulin sensitivity.
/// All fields are optional (data may not be available for a given day).
struct GarminContextSnapshot: Codable {
    let queryTime: Date

    // MARK: - Daily Summary (from dailySummaries collection)

    let restingHeartRateInBeatsPerMinute: Int?
    let averageHeartRateInBeatsPerMinute: Int?
    let averageStressLevel: Int? // 1-100, or -1 if insufficient data
    let maxStressLevel: Int?
    let stressDurationInSeconds: Int?
    let restStressDurationInSeconds: Int?
    let lowStressDurationInSeconds: Int?
    let mediumStressDurationInSeconds: Int?
    let highStressDurationInSeconds: Int?
    let stressQualifier: String? // "calm", "balanced", "stressful", "very_stressful"
    let steps: Int?
    let activeKilocalories: Int?
    let moderateIntensityDurationInSeconds: Int?
    let vigorousIntensityDurationInSeconds: Int?
    let bodyBatteryChargedValue: Int?
    let bodyBatteryDrainedValue: Int?

    // MARK: - Yesterday's Daily Summary (for delayed sensitivity effects)

    let yesterdaySteps: Int?
    let yesterdayActiveKilocalories: Int?
    let yesterdayModerateIntensityDurationInSeconds: Int?
    let yesterdayVigorousIntensityDurationInSeconds: Int?

    // MARK: - Sleep Summary

    let sleepDurationInSeconds: Int?
    let deepSleepDurationInSeconds: Int?
    let lightSleepDurationInSeconds: Int?
    let remSleepInSeconds: Int?
    let awakeDurationInSeconds: Int?
    let sleepScoreValue: Int? // 0-100
    let sleepScoreQualifier: String? // EXCELLENT/GOOD/FAIR/POOR
    let sleepValidation: String? // AUTO_FINAL, ENHANCED_FINAL, etc.

    // MARK: - Stress Details (extracted from timelines)

    let currentBodyBattery: Int? // latest BB reading
    let bodyBatteryAtWake: Int? // earliest BB of the day (recovery proxy)
    let currentStressLevel: Int? // latest stress (1-100, positive only)

    // MARK: - HRV Summary

    let lastNightAvg: Int? // lastNightAvg HRV (RMSSD ms)
    let lastNight5MinHigh: Int? // max 5-min HRV window

    // MARK: - User Metrics

    let vo2Max: Double?
    let fitnessAge: Int?

    // MARK: - 7-Day Averages (computed from historical documents)

    let restingHR7DayAvg: Int?
    let hrvWeeklyAvg: Int?

    // MARK: - Computed Deltas

    /// Resting HR delta from 7-day average (positive = elevated = more resistant)
    var restingHRDelta: Int? {
        guard let current = restingHeartRateInBeatsPerMinute, let avg = restingHR7DayAvg else { return nil }
        return current - avg
    }

    /// HRV delta as percentage from weekly average (negative = suppressed = more resistant)
    var hrvDeltaPercent: Double? {
        guard let current = lastNightAvg, let avg = hrvWeeklyAvg, avg > 0 else { return nil }
        return (Double(current - avg) / Double(avg)) * 100
    }

    /// Total sleep in minutes
    var totalSleepMinutes: Int? {
        guard let seconds = sleepDurationInSeconds else { return nil }
        return seconds / 60
    }

    /// Total intensity minutes today (moderate + vigorous)
    var intensityMinutesToday: Int? {
        let moderate = (moderateIntensityDurationInSeconds ?? 0) / 60
        let vigorous = (vigorousIntensityDurationInSeconds ?? 0) / 60
        let total = moderate + vigorous
        return total > 0 ? total : nil
    }

    /// Yesterday's total intensity minutes
    var yesterdayIntensityMinutes: Int? {
        let moderate = (yesterdayModerateIntensityDurationInSeconds ?? 0) / 60
        let vigorous = (yesterdayVigorousIntensityDurationInSeconds ?? 0) / 60
        let total = moderate + vigorous
        return total > 0 ? total : nil
    }

    /// Yesterday's vigorous minutes
    var yesterdayVigorousMinutes: Int? {
        guard let seconds = yesterdayVigorousIntensityDurationInSeconds, seconds > 0 else { return nil }
        return seconds / 60
    }
}
