import Foundation

struct MealCob {
    /// Internal structure to keep track of bucketed glucose values
    struct BucketedGlucose {
        let glucose: Decimal
        let date: Date
    }

    /// Result structure for carb absorption detection
    struct CobResult {
        let carbsAbsorbed: Decimal
        let currentDeviation: Decimal
        let maxDeviation: Decimal
        let minDeviation: Decimal
        let slopeFromMaxDeviation: Decimal
        let slopeFromMinDeviation: Decimal
        let allDeviations: [Decimal]
    }

    /// Detects carb absorption by analyzing glucose deviations from expected insulin activity
    ///
    /// This is the main COB detection algorithm entry point
    static func detectCarbAbsorption(
        glucose: [BloodGlucose],
        pumpHistory: [PumpHistoryEvent],
        basalProfile: [BasalProfileEntry],
        profile: Profile,
        mealDate: Date,
        ciDate: Date?
    ) throws -> CobResult {
        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory.map { $0.computedEvent() },
            profile: profile,
            clock: mealDate,
            autosens: nil,
            zeroTempDuration: nil
        )

        let bucketedData = try bucketGlucoseForCob(
            glucose: glucose,
            profile: profile,
            mealDate: mealDate,
            ciDate: ciDate
        )

        return try calculateCarbAbsorption(
            bucketedData: bucketedData,
            treatments: treatments,
            basalProfile: basalProfile,
            profile: profile,
            mealDate: mealDate,
            ciDate: ciDate
        )
    }

    /// Groups glucose readings into time buckets with interpolation for missing data points
    private static func bucketGlucoseForCob(
        glucose: [BloodGlucose],
        profile: Profile,
        mealDate: Date,
        ciDate: Date?
    ) throws -> [BucketedGlucose] {
        let glucoseData = glucose.compactMap({ (bg: BloodGlucose) -> BucketedGlucose? in
            guard let glucose = bg.glucose ?? bg.sgv else { return nil }
            return BucketedGlucose(glucose: Decimal(glucose), date: bg.dateString)
        })

        guard let first = glucoseData.first else { return [] }

        var bucketedData = [first]
        var foundPreMealBG = false
        var lastBgIndex = 0

        for i in 1 ..< glucoseData.count {
            let currentGlucose = glucoseData[i]
            let bgTime = currentGlucose.date

            // Skip invalid glucose readings
            guard currentGlucose.glucose >= 39 else {
                continue
            }

            // Only consider BGs for maxMealAbsorptionTime hours after a meal
            let hoursAfterMeal = Decimal(bgTime.timeIntervalSince(mealDate)) / 3600
            if hoursAfterMeal > profile.maxMealAbsorptionTime || foundPreMealBG {
                continue
            } else if hoursAfterMeal < 0 {
                foundPreMealBG = true
            }

            // In CI mode, only consider last ~45m of data
            if let ciDate = ciDate {
                let hoursAgo = ciDate.timeIntervalSince(bgTime) / (45 * 60)
                if hoursAgo > 1 || hoursAgo < 0 {
                    continue
                }
            }

            // Determine last BG time
            let lastBgTime: Date
            if let lastDate = bucketedData.last?.date {
                lastBgTime = lastDate
            } else if lastBgIndex < glucoseData.count, lastBgIndex >= 0 {
                lastBgTime = glucoseData[lastBgIndex].date
            } else {
                throw CobError.couldNotDetermineLastBgTime
            }

            let elapsedMinutes = bgTime.timeIntervalSince(lastBgTime) / 60

            if abs(elapsedMinutes) > 8 {
                // Interpolate missing data points
                let lastBg = bucketedData.last?.glucose ?? glucoseData[lastBgIndex].glucose
                // Cap interpolation at a maximum of 4h
                let cappedElapsedMinutes = Decimal(min(240, abs(elapsedMinutes)))
                var remainingMinutes = cappedElapsedMinutes
                var interpolationTime = lastBgTime
                var interpolationBg = lastBg

                while remainingMinutes > 5 {
                    let previousBgTime = interpolationTime.addingTimeInterval(-5 * 60)
                    let gapDelta = currentGlucose.glucose - lastBg
                    let previousBg = interpolationBg + (5 / cappedElapsedMinutes * gapDelta)

                    bucketedData.append(BucketedGlucose(
                        glucose: previousBg.rounded(),
                        date: previousBgTime
                    ))

                    remainingMinutes -= 5
                    interpolationBg = previousBg
                    interpolationTime = previousBgTime
                }
            } else if abs(elapsedMinutes) > 2 {
                bucketedData.append(currentGlucose)
            } else {
                // Average with previous reading
                if let lastIndex = bucketedData.indices.last {
                    let averageGlucose = (bucketedData[lastIndex].glucose + currentGlucose.glucose) / 2
                    bucketedData[lastIndex] = BucketedGlucose(
                        glucose: averageGlucose,
                        date: bucketedData[lastIndex].date
                    )
                }
            }

            lastBgIndex = i
        }

        return bucketedData
    }

    /// Calculates carb absorption and related metrics from bucketed glucose data
    private static func calculateCarbAbsorption(
        bucketedData: [BucketedGlucose],
        treatments: [ComputedPumpHistoryEvent],
        basalProfile: [BasalProfileEntry],
        profile: Profile,
        mealDate: Date,
        ciDate: Date?
    ) throws -> CobResult {
        var carbsAbsorbed: Decimal = 0
        var currentDeviation: Decimal = 0
        var slopeFromMaxDeviation: Decimal = 0
        var slopeFromMinDeviation: Decimal = 999
        var maxDeviation: Decimal = 0
        var minDeviation: Decimal = 999
        var allDeviations: [Decimal] = []

        // Process bucketed data (excluding last 3 entries to avoid incomplete deltas)
        for i in 0 ..< (bucketedData.count - 3) {
            let bgTime = bucketedData[i].date
            let bg = bucketedData[i].glucose

            // Skip invalid glucose readings
            guard bg >= 39, bucketedData[i + 3].glucose >= 39 else {
                continue
            }

            guard let isfProfile = profile.isfProfile?.toInsulinSensitivities() else {
                throw CobError.missingIsfProfile
            }
            let (sensitivity, _) = try Isf.isfLookup(isfDataInput: isfProfile, timestamp: bgTime)
            guard sensitivity > 0 else {
                throw CobError.isfLookupError
            }

            let avgDelta = (bg - bucketedData[i + 3].glucose) / 3
            let delta = bg - bucketedData[i + 1].glucose

            var simulationProfile = profile
            simulationProfile.currentBasal = try Basal.basalLookup(basalProfile, now: bgTime)

            let iob = try IobCalculation.iobTotal(treatments: treatments, profile: simulationProfile, time: bgTime)

            // Copying Javascript rounding
            let bgi: Decimal = (-iob.activity * sensitivity * 5 * 100 + 0.5).rounded(scale: 0, roundingMode: .down) / 100
            let deviation = delta - bgi

            // Calculate the deviation right now, for use in min_5m
            if i == 0 {
                currentDeviation = ((avgDelta - bgi) * 1000).rounded() / 1000
                if let ciDate = ciDate, ciDate > bgTime {
                    allDeviations.append(currentDeviation.rounded())
                }
            } else if let ciDate = ciDate, ciDate > bgTime {
                let avgDeviation = ((avgDelta - bgi) * 1000).rounded() / 1000
                let deviationSlope = (avgDeviation - currentDeviation) / Decimal(bgTime.timeIntervalSince(ciDate)) * 1000 * 60 * 5

                if avgDeviation > maxDeviation {
                    slopeFromMaxDeviation = min(0, deviationSlope)
                    maxDeviation = avgDeviation
                }
                if avgDeviation < minDeviation {
                    slopeFromMinDeviation = max(0, deviationSlope)
                    minDeviation = avgDeviation
                }

                allDeviations.append(avgDeviation.rounded())
            }

            // If bgTime is more recent than mealTime
            if bgTime > mealDate {
                guard let carbRatio = profile.carbRatio else {
                    throw CobError.missingCarbRatioInProfile
                }

                // Figure out how many carbs that represents
                let ci = max(deviation, currentDeviation / 2, profile.min5mCarbImpact)
                let absorbed = ci * carbRatio / sensitivity
                carbsAbsorbed += absorbed
            }
        }

        return CobResult(
            carbsAbsorbed: carbsAbsorbed,
            currentDeviation: currentDeviation,
            maxDeviation: maxDeviation,
            minDeviation: minDeviation,
            slopeFromMaxDeviation: slopeFromMaxDeviation,
            slopeFromMinDeviation: slopeFromMinDeviation,
            allDeviations: allDeviations
        )
    }
}

/// Error types for COB calculation
enum CobError: Error {
    case missingIsfProfile
    case isfLookupError
    case missingCarbRatioInProfile
    case couldNotDetermineLastBgTime
}
