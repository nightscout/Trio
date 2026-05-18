import Foundation

struct MealCob {
    /// Internal structure to keep track of bucketed glucose values
    struct BucketedGlucose: Codable {
        let glucose: Decimal
        let date: Date

        func average(adding glucose: BucketedGlucose) -> BucketedGlucose {
            // BUG: simple average of two values
            let newGlucose = (self.glucose + glucose.glucose) / 2
            return BucketedGlucose(glucose: newGlucose, date: date)
        }
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
    ///
    /// IMPORTANT: This implementation faithfully reproduces JavaScript bugs where:
    /// - clock gets mutated to the last bgTime processed
    /// - profile.currentBasal gets mutated to the basal rate at that time
    /// These mutations persist between calls, affecting subsequent COB calculations
    static func detectCarbAbsorption(
        clock: inout Date, // Made inout to match JS mutation bug
        glucose: [BloodGlucose],
        pumpHistory: [PumpHistoryEvent],
        basalProfile: [BasalProfileEntry],
        profile: inout Profile, // Made inout to match JS mutation bug
        mealDate: Date,
        carbImpactDate: Date?
    ) throws -> CobResult {
        let treatments = try IobHistory.calcTempTreatments(
            history: pumpHistory.map { $0.computedEvent() },
            profile: profile,
            clock: clock,
            autosens: nil,
            zeroTempDuration: nil
        )

        let bucketedData = try bucketGlucoseForCob(
            glucose: glucose,
            profile: profile,
            mealDate: mealDate,
            carbImpactDate: carbImpactDate
        )

        return try calculateCarbAbsorption(
            bucketedData: bucketedData,
            treatments: treatments,
            basalProfile: basalProfile,
            profile: &profile,
            mealDate: mealDate,
            carbImpactDate: carbImpactDate,
            clock: &clock
        )
    }

    /// Groups glucose readings into time buckets with interpolation for missing data points
    /// Faithful port of JS bucketing logic including all quirks
    static func bucketGlucoseForCob(
        glucose: [BloodGlucose],
        profile: Profile,
        mealDate: Date,
        carbImpactDate: Date?
    ) throws -> [BucketedGlucose] {
        // Map glucose data like JS does
        let glucoseData = glucose.compactMap({ (bg: BloodGlucose) -> BucketedGlucose? in
            guard let glucose = bg.glucose ?? bg.sgv else { return nil }
            return BucketedGlucose(glucose: Decimal(glucose), date: bg.dateString)
        })

        var bucketedData: [BucketedGlucose] = []
        var foundPreMealBG = false
        var lastbgi = 0

        // Initialize first bucket if we have data
        guard !glucoseData.isEmpty else { return [] }

        // JS behavior: check if first glucose is valid
        if glucoseData[0].glucose < 39 {
            lastbgi = -1
        }

        bucketedData.append(glucoseData[0])
        var j = 0

        for i in 1 ..< glucoseData.count {
            let bgTime = glucoseData[i].date
            var lastbgTime: Date

            // Skip invalid glucose
            if glucoseData[i].glucose < 39 {
                continue
            }

            // JS: only consider BGs for maxMealAbsorptionTime after a meal
            let hoursAfterMeal = bgTime.timeIntervalSince(mealDate) / (60 * 60)
            if hoursAfterMeal > Double(profile.maxMealAbsorptionTime) || foundPreMealBG {
                continue
            } else if hoursAfterMeal < 0 {
                foundPreMealBG = true
            }

            // Only consider last ~45m of data in CI mode
            if let carbImpactDate = carbImpactDate {
                let hoursAgo = carbImpactDate.timeIntervalSince(bgTime) / (45 * 60)
                if hoursAgo > 1 || hoursAgo < 0 {
                    continue
                }
            }

            // Get last bg time - JS logic
            // Note display_time isn't set in Trio so this is the
            // only logic that will trigger
            if lastbgi >= 0, lastbgi < glucoseData.count {
                lastbgTime = glucoseData[lastbgi].date
            } else {
                continue
            }

            var elapsedMinutes = bgTime.timeIntervalSince(lastbgTime) / 60

            if abs(elapsedMinutes) > 8 {
                // Interpolate missing data points - JS logic with all its quirks
                var lastbg = lastbgi >= 0 && lastbgi < glucoseData.count ? glucoseData[lastbgi].glucose : bucketedData[j].glucose
                // Cap at 4 hours like JS AND modify the variable
                elapsedMinutes = min(240, abs(elapsedMinutes))

                while elapsedMinutes > 5 {
                    // JS creates previousbgTime by subtracting from lastbgTime
                    let previousbgTime = lastbgTime.addingTimeInterval(-5 * 60)
                    j += 1

                    let gapDelta = glucoseData[i].glucose - lastbg
                    // JS uses the capped elapsed_minutes value
                    let previousbg = lastbg + (5 / Decimal(elapsedMinutes)) * gapDelta

                    let interpolatedBucket = BucketedGlucose(
                        glucose: previousbg.rounded(scale: 0),
                        date: previousbgTime
                    )
                    bucketedData.append(interpolatedBucket)

                    elapsedMinutes -= 5
                    lastbg = previousbg
                    lastbgTime = previousbgTime
                }
                // JS behavior: Do NOT add the actual glucose reading after interpolation

            } else if abs(elapsedMinutes) > 2 {
                // Add new sample
                j += 1
                bucketedData.append(BucketedGlucose(
                    glucose: glucoseData[i].glucose,
                    date: bgTime
                ))
            } else {
                // Average with previous
                bucketedData[j] = bucketedData[j].average(adding: glucoseData[i])
            }

            lastbgi = i
        }

        return bucketedData
    }

    /// Calculates carb absorption and related metrics from bucketed glucose data
    /// Faithful port including JS bugs where clock and profile are mutated
    private static func calculateCarbAbsorption(
        bucketedData: [BucketedGlucose],
        treatments: [ComputedPumpHistoryEvent],
        basalProfile: [BasalProfileEntry],
        profile: inout Profile, // Mutated to match JS bug
        mealDate: Date,
        carbImpactDate: Date?,
        clock: inout Date // Mutated to match JS bug
    ) throws -> CobResult {
        var carbsAbsorbed: Decimal = 0
        var currentDeviation: Decimal = 0
        var slopeFromMaxDeviation: Decimal = 0
        var slopeFromMinDeviation: Decimal = 999
        var maxDeviation: Decimal = 0
        var minDeviation: Decimal = 999
        var allDeviations: [Decimal] = []

        // Process bucketed data (excluding last 3 entries)
        for i in 0 ..< max(0, bucketedData.count - 3) {
            let bgTime = bucketedData[i].date
            let bg = bucketedData[i].glucose

            // Skip if glucose values are invalid
            guard bg >= 39, bucketedData[i + 3].glucose >= 39 else {
                continue
            }

            let avgDelta = ((bg - bucketedData[i + 3].glucose) / 3).jsRounded(scale: 2)
            let delta = bg - bucketedData[i + 1].glucose

            // Get ISF
            guard let isfProfile = profile.isfProfile?.toInsulinSensitivities() else {
                throw CobError.missingIsfProfile
            }
            let (sens, _) = try Isf.isfLookup(isfDataInput: isfProfile, timestamp: bgTime)

            // JS BUGS: These mutations persist!
            clock = bgTime // Mutates the clock
            profile.currentBasal = try Basal.basalLookup(basalProfile, now: bgTime) // Mutates the profile

            // Calculate IOB with mutated values
            let iob = try IobCalculation.iobTotal(
                treatments: treatments,
                profile: profile,
                time: clock // Uses the mutated clock
            )

            // JS: bgi = Math.round(( -iob.activity * sens * 5 )*100)/100
            let bgi: Decimal = (-iob.activity * sens * 5).jsRounded(scale: 2)
            let deviation = delta - bgi

            // Calculate current deviation
            if i == 0 {
                // JS: currentDeviation = Math.round((avgDelta-bgi)*1000)/1000
                currentDeviation = (avgDelta - bgi).jsRounded(scale: 3)
                if let carbImpactDate = carbImpactDate, carbImpactDate > bgTime {
                    allDeviations.append(currentDeviation.rounded())
                }
            } else if let carbImpactDate = carbImpactDate, carbImpactDate > bgTime {
                // JS: avgDeviation = Math.round((avgDelta-bgi)*1000)/1000
                let avgDeviation = (avgDelta - bgi).jsRounded(scale: 3)
                // JS: deviationSlope = (avgDeviation-currentDeviation)/(bgTime-ciTime)*1000*60*5
                // we can drop the *1000 since we're already in seconds
                let deviationSlope = (avgDeviation - currentDeviation) /
                    Decimal(bgTime.timeIntervalSince(carbImpactDate)) * 60 * 5

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

            // Calculate carbs absorbed
            if bgTime > mealDate {
                guard let carbRatio = profile.carbRatio else {
                    throw CobError.missingCarbRatioInProfile
                }

                // JS: ci = Math.max(deviation, currentDeviation/2, profile.min_5m_carbimpact)
                let ci = max(deviation, currentDeviation / 2, profile.min5mCarbImpact)
                let absorbed = ci * carbRatio / sens
                carbsAbsorbed += absorbed
            }
        }

        // IMPORTANT: clock and profile.currentBasal remain mutated after this function returns!

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
    case couldNotDetermineLastglucoseTime
}
