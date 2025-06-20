import Foundation

struct MealCob {
    /// Internal structure to keep track of bucketed glucose values
    struct BucketedGlucose: Codable {
        let glucose: Decimal
        let date: Date
        let samplesInBucket: Int

        func average(adding glucose: BucketedGlucose) -> BucketedGlucose {
            let total = Decimal(samplesInBucket) * self.glucose + glucose.glucose
            let numSamples = samplesInBucket + 1
            let newGlucoseAverage = total / Decimal(numSamples)
            return BucketedGlucose(glucose: newGlucoseAverage, date: date, samplesInBucket: numSamples)
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
    static func detectCarbAbsorption(
        glucose: [BloodGlucose],
        pumpHistory: [PumpHistoryEvent],
        basalProfile: [BasalProfileEntry],
        profile: Profile,
        mealDate: Date,
        carbImpactDate: Date?
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
            carbImpactDate: carbImpactDate
        )

        return try calculateCarbAbsorption(
            bucketedData: bucketedData,
            treatments: treatments,
            basalProfile: basalProfile,
            profile: profile,
            mealDate: mealDate,
            carbImpactDate: carbImpactDate
        )
    }

    private static func interpolateGlucose(lastBucket: BucketedGlucose, glucose: BucketedGlucose) -> [BucketedGlucose] {
        let deltaGlucose = glucose.glucose - lastBucket.glucose
        let timeBetweenSamples = Decimal(lastBucket.date.timeIntervalSince(glucose.date))
        let slope = deltaGlucose / timeBetweenSamples
        let stepSize = Decimal(5.minutesToSeconds)

        // I'm skipping the 4 hour limit from JS
        // Note: in the JS implementation it does not add the `glucose`
        // value to the bucket, so we will retain this behavior here
        // to ensure mostly consistent timing between samples. In other
        // words, JS only adds interpolated values, not the actual reading
        let interpolatedValues = stride(from: stepSize, to: timeBetweenSamples, by: stepSize).map { time in
            let newGlucose = lastBucket.glucose + slope * time
            let newDate = lastBucket.date - TimeInterval(time)
            return BucketedGlucose(glucose: newGlucose, date: newDate, samplesInBucket: 1)
        }

        return interpolatedValues
    }

    /// Groups glucose readings into time buckets with interpolation for missing data points
    /// Make this non-private to expose for test cases
    static func bucketGlucoseForCob(
        glucose: [BloodGlucose],
        profile: Profile,
        mealDate: Date,
        carbImpactDate: Date?
    ) throws -> [BucketedGlucose] {
        var glucoseData = glucose.compactMap({ (bg: BloodGlucose) -> BucketedGlucose? in
            guard let glucose = bg.glucose ?? bg.sgv else { return nil }
            return BucketedGlucose(glucose: Decimal(glucose), date: bg.dateString, samplesInBucket: 1)
        })

        var bucketedData: [BucketedGlucose] = []

        // make sure that all of our samples are later than the meal and
        // before the maxMealAbsorptionTime expires. We also added a
        // >= 39 glucose check from Javascript
        let mealDoneDate = mealDate + profile.maxMealAbsorptionTime.hoursToSeconds
        glucoseData = glucoseData.filter { $0.date >= mealDate && $0.date <= mealDoneDate && $0.glucose >= 39 }

        // Only consider last ~45m of data in CI mode
        // this allows us to calculate deviations for the last ~30m
        if let carbImpactDate = carbImpactDate {
            glucoseData = glucoseData
                .filter { carbImpactDate >= $0.date && carbImpactDate.timeIntervalSince($0.date) <= 45.minutesToSeconds }
        }

        for glucose in glucoseData {
            guard let lastBucket = bucketedData.last else {
                bucketedData.append(glucose)
                continue
            }
            let timeBetweenSamples = lastBucket.date.timeIntervalSince(glucose.date)
            let elapsedTime = timeBetweenSamples > 4.hoursToSeconds ? 4.hoursToSeconds : timeBetweenSamples
            if elapsedTime > 8.minutesToSeconds {
                // interpolate
                let interpolatedGlucose = interpolateGlucose(lastBucket: lastBucket, glucose: glucose)
                bucketedData.append(contentsOf: interpolatedGlucose)
            } else if elapsedTime > 2.minutesToSeconds {
                // add the new sample
                bucketedData.append(BucketedGlucose(glucose: glucose.glucose, date: glucose.date, samplesInBucket: 1))
            } else {
                // average
                bucketedData = Array(bucketedData.dropLast())
                bucketedData.append(lastBucket.average(adding: glucose))
            }
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
        carbImpactDate: Date?
    ) throws -> CobResult {
        var carbsAbsorbed: Decimal = 0
        var currentDeviation: Decimal = 0
        var slopeFromMaxDeviation: Decimal = 0
        var slopeFromMinDeviation: Decimal = 999
        var maxDeviation: Decimal = 0
        var minDeviation: Decimal = 999
        var allDeviations: [Decimal] = []

        // Process bucketed data (excluding last 3 entries to avoid incomplete deltas)
        // If bucketed data < 4, skips loop and just returns default values, matching JS behavior
        for bucketCount in 0 ..< max(0, bucketedData.count - 3) {
            let glucoseTime = bucketedData[bucketCount].date
            let glucose = bucketedData[bucketCount].glucose

            // Skip invalid glucose readings
            guard glucose >= 39, bucketedData[bucketCount + 3].glucose >= 39 else {
                continue
            }

            guard let isfProfile = profile.isfProfile?.toInsulinSensitivities() else {
                throw CobError.missingIsfProfile
            }
            let (sensitivity, _) = try Isf.isfLookup(isfDataInput: isfProfile, timestamp: glucoseTime)
            guard sensitivity > 0 else {
                throw CobError.isfLookupError
            }

            let avgDelta = (glucose - bucketedData[bucketCount + 3].glucose) / 3
            let delta = glucose - bucketedData[bucketCount + 1].glucose

            var simulationProfile = profile
            simulationProfile.currentBasal = try Basal.basalLookup(basalProfile, now: glucoseTime)

            let iob = try IobCalculation.iobTotal(treatments: treatments, profile: simulationProfile, time: glucoseTime)

            // Copying Javascript rounding
            // JS oref calls this "big" = "blood glucose impact"
            let glucoseImpact: Decimal = (-iob.activity * sensitivity * 5 * 100 + 0.5)
                .rounded(scale: 0, roundingMode: .down) / 100
            let deviation = delta - glucoseImpact

            // Calculate the deviation right now, for use in min_5m
            if bucketCount == 0 {
                currentDeviation = ((avgDelta - glucoseImpact) * 1000).rounded() / 1000
                if let carbImpactDate = carbImpactDate, carbImpactDate > glucoseTime {
                    allDeviations.append(currentDeviation.rounded())
                }
            } else if let carbImpactDate = carbImpactDate, carbImpactDate > glucoseTime {
                let avgDeviation = ((avgDelta - glucoseImpact) * 1000).rounded() / 1000
                let deviationSlope = (avgDeviation - currentDeviation) / Decimal(glucoseTime.timeIntervalSince(carbImpactDate)) *
                    1000 * 60 * 5

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

            // If glucoseTime is more recent than mealTime
            if glucoseTime > mealDate {
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
    case couldNotDetermineLastglucoseTime
}
