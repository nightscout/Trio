import Foundation

extension DeterminationGenerator {
    /// helper struct for managing glucose
    private struct GlucoseReading {
        let glucose: Int
        let date: Date
        let noise: Int?
    }

    /// Smooths given CGM readings, and computes rolling delta statistics
    /// (i.e., last, short-term, and long-term).
    ///
    /// Mirrors JavaScript oref `glucose-get-last.js` logic.
    ///
    /// - Returns: A `GlucoseStatus` containing:
    ///   - `glucose`: the most recent glucose value (mg/dL),
    ///   - `delta`: the 5-minute delta (mg/dL per 5m),
    ///   - `shortAvgDelta`: the average delta over ~5–15 minutes,
    ///   - `longAvgDelta`: the average delta over ~20–40 minutes,
    ///   - `noise`: the CGM noise level (if any),
    ///   - `date`: the timestamp of the “now” reading,
    ///   - `lastCalIndex`: index of the last calibration record (always `nil` here),
    ///   - `device`: the source device string.
    ///
    /// - Throws: Any `CoreDataError` or other error encountered during fetch or context work.
    /// - Returns: `nil` if no valid glucose readings are found in the past day.
    static func getGlucoseStatus(glucoseReadings: [BloodGlucose]) throws -> GlucoseStatus? {
        // FIXME: put this here for now; use implementation in GlucoseStorage later (already implemented and commented out for now)

        let glucoseReadings = glucoseReadings.compactMap { reading -> GlucoseReading? in
            guard let glucose = reading.glucose ?? reading.sgv else { return nil }
            return GlucoseReading(glucose: glucose, date: reading.dateString, noise: reading.noise)
        }

        guard glucoseReadings.isNotEmpty else {
            return nil
        }

        // Sort descending (newest first)
        let sorted = glucoseReadings.sorted { $0.date > $1.date }

        guard let mostRecentGlucose = sorted.first else { return nil }
        var mostRecentGlucoseReading = Decimal(mostRecentGlucose.glucose)
        var mostRecentGlucoseDate: Date = mostRecentGlucose.date

        var lastDeltas: [Decimal] = []
        var shortDeltas: [Decimal] = []
        var longDeltas: [Decimal] = []

        // Walk older entries to compute deltas
        for entry in sorted.dropFirst() {
            // JS oref has logic here around skipping calibration readings.
            // We never calibration record (never happens here, since type=="sgv")
            // so we omit this check

            // only use readings >38 mg/dL (to skip code values, <39)
            guard entry.glucose > 38 else { continue }

            let minutesAgo = (mostRecentGlucoseDate.timeIntervalSince(entry.date) / 60).rounded()
            // compute mg/dL per 5 m as a Decimal:
            let change = mostRecentGlucoseReading - Decimal(entry.glucose)

            // very-recent (<2.5 m) smooths "now"
            if minutesAgo > -2, minutesAgo <= 2.5 {
                mostRecentGlucoseReading = (mostRecentGlucoseReading + Decimal(entry.glucose)) / 2
                mostRecentGlucoseDate = Date(
                    timeIntervalSince1970: (
                        mostRecentGlucoseDate.timeIntervalSince1970 + entry.date
                            .timeIntervalSince1970
                    ) / 2
                )
            }
            // short window (~5–15 m)
            else if minutesAgo > 2.5, minutesAgo <= 17.5 {
                let avgDelta = (change / Decimal(minutesAgo)) * Decimal(5)
                shortDeltas.append(avgDelta)
                if minutesAgo < 7.5 {
                    lastDeltas.append(avgDelta)
                }
            }
            // long window (~20–40 m)
            else if minutesAgo > 17.5, minutesAgo < 42.5 {
                let avgDelta = (change / Decimal(minutesAgo)) * Decimal(5)
                longDeltas.append(avgDelta)
            }
        }

        // compute means (or zero)
        let lastDelta: Decimal = lastDeltas.mean
        let shortAvg: Decimal = shortDeltas.mean
        let longAvg: Decimal = longDeltas.mean

        return GlucoseStatus(
            delta: lastDelta.jsRounded(scale: 2),
            glucose: mostRecentGlucoseReading,
            noise: Int(sorted[0].noise ?? 0),
            shortAvgDelta: shortAvg.jsRounded(scale: 2),
            longAvgDelta: longAvg.jsRounded(scale: 2),
            date: mostRecentGlucoseDate,
            lastCalIndex: nil,
            device: "", // FIXME: will be filled once this gets moved back to GlucoseStorage
        )
    }

    static func calculateExpectedDelta(
        targetGlucose: Decimal,
        eventualGlucose: Decimal,
        glucoseImpact: Decimal
    ) -> Decimal {
        // JS expects glucose to rise/fall at rate of glucose impact
        // adjusted by the rate at which glucose would need to rise/fall
        // to move eventual glucose to target over a 2 hr window
        // TODO: expects that glucose can only be available in 5min chunks. do we need to change this handling?

        let fiveMinuteBlocks = Decimal((2 * 60) / 5)
        let delta = targetGlucose - eventualGlucose
        return (glucoseImpact + (delta / fiveMinuteBlocks)).jsRounded(scale: 1)
    }

    static func calculateSensitivityRatio(
        currentGlucose: Decimal,
        profile: Profile,
        autosens: Autosens?,
        targetGlucose: Decimal,
        temptargetSet: Bool,
        dynamicIsfResult: DynamicISFResult?
    ) -> (Decimal, Bool) {
        let normalTarget: Decimal = 100
        let halfBasalTarget = profile.halfBasalExerciseTarget
        var ratio: Decimal = 1
        var updateAutosensRatio = false

        // High temp target raises sensitivity or low temp lowers it
        if (profile.highTemptargetRaisesSensitivity && temptargetSet && targetGlucose > normalTarget) ||
            (profile.lowTemptargetLowersSensitivity && temptargetSet && targetGlucose < normalTarget)
        {
            let c = halfBasalTarget - normalTarget
            if c * (c + targetGlucose - normalTarget) <= 0 {
                ratio = profile.autosensMax
            } else {
                ratio = c / (c + targetGlucose - normalTarget)
            }
            ratio = min(ratio, profile.autosensMax).jsRounded(scale: 2)
        } else if let autosens = autosens {
            // Use autosens if present
            ratio = autosens.ratio
        }

        if let autosens = autosens {
            // Increase the dynamic ratio when using a low temp target
            if profile.temptargetSet == true, targetGlucose < normalTarget, let dynamicIsfResult = dynamicIsfResult,
               currentGlucose >= targetGlucose
            {
                if ratio < dynamicIsfResult.ratio {
                    ratio = dynamicIsfResult.ratio * (normalTarget / targetGlucose)
                    // Use autosesns.max limit
                    ratio = min(ratio, profile.autosensMax).jsRounded(scale: 2)
                    updateAutosensRatio = true
                }
            }
        }

        return (ratio, updateAutosensRatio)
    }

    static func computeAdjustedBasal(
        profile: Profile,
        currentBasalRate: Decimal,
        sensitivityRatio: Decimal,
        overrideFactor: Decimal
    ) -> Decimal {
        let adjustedBasal = currentBasalRate * sensitivityRatio * overrideFactor
        return TempBasalFunctions.roundBasal(profile: profile, basalRate: adjustedBasal)
    }

    static func computeAdjustedSensitivity(
        sensitivity: Decimal,
        sensitivityRatio: Decimal,
        trioCustomOrefVariables: TrioCustomOrefVariables
    ) -> Decimal {
        let sensitivity = trioCustomOrefVariables.override(sensitivity: sensitivity)
        guard sensitivityRatio != 1.0 else { return sensitivity.jsRounded(scale: 1) }
        return (sensitivity / sensitivityRatio).jsRounded(scale: 1)
    }

    /// Checks if current temp basal matches last temp from IOB data.
    /// Returns nil if check passes, or the failure reason string if it fails.
    static func checkCurrentTempBasalRateSafety(
        currentTemp: TempBasal,
        lastTempTarget: IobResult.LastTemp?,
        currentTime: Date
    ) -> String? {
        guard let lastTemp = lastTempTarget, let lastTempDate = lastTemp.timestamp,
              let lastTempDuration = lastTemp.duration else { return nil }
        // TODO: throw error for malformed IobResult? Can this be malformed?

        let lastTempAge = Int((currentTime.timeIntervalSince(lastTempDate) / 60).rounded()) // in minutes
//        let tempModulus = Int(lastTempAge + currentTemp.duration) % 30 // only used in JS as output; will leave it here for now

        if let lastTempRate = lastTemp.rate, currentTemp.rate != lastTempRate, lastTempAge > 10, currentTemp.duration > 0 {
            // Rates don't match and temp is old: cancel temp
            return "Warning: currenttemp rate \(currentTemp.rate) != lastTemp rate \(lastTempRate) from pumphistory; canceling temp"
        }
        if currentTemp.duration > 0 {
            let lastTempEnded = Decimal(lastTempAge) - lastTempDuration

            if lastTempEnded > 5, lastTempAge > 10 {
                // Last temp ended long ago but temp is running: cancel temp
                return "Warning: currenttemp running but lastTemp from pumphistory ended \(lastTempEnded.jsRounded(scale: 2))m ago; canceling temp"
            }
        }

        return nil
    }

    /// Adjust glucose targets (min, max, target) based on autosens and/or noise.
    /// - Returns: adjusted targets and new threshold
    static func adjustGlucoseTargets(
        profile: Profile,
        autosens: Autosens?,
        trioCustomOrefVariables: TrioCustomOrefVariables,
        temptargetSet: Bool,
        targetGlucose: Decimal,
        minGlucose: Decimal,
        maxGlucose: Decimal,
        noise: Int
    ) -> (targets: AdjustedGlucoseTargets, threshold: Decimal) {
        var minGlucose = minGlucose
        var maxGlucose = maxGlucose
        var targetGlucose = targetGlucose

        // Apply profile override first
        if let overrideTarget = profile.profileTarget(trioCustomOrefVariables: trioCustomOrefVariables) {
            targetGlucose = overrideTarget
            minGlucose = overrideTarget
            maxGlucose = overrideTarget
        }

        // Only adjust glucose targets for autosens if no temp target set
        if !temptargetSet, let autosens = autosens {
            if (profile.sensitivityRaisesTarget && autosens.ratio < 1) ||
                (profile.resistanceLowersTarget && autosens.ratio > 1)
            {
                minGlucose = ((minGlucose - 60) / autosens.ratio + 60).jsRounded()
                maxGlucose = ((maxGlucose - 60) / autosens.ratio + 60).jsRounded()
                targetGlucose = max(80, ((targetGlucose - 60) / autosens.ratio + 60).jsRounded())
            }
        }

        // Raise target for noisy/CGM data
        if noise >= 2 {
            let noisyCGMTargetMultiplier = max(1.1, profile.noisyCGMTargetMultiplier)
            minGlucose = min(200, minGlucose * noisyCGMTargetMultiplier).jsRounded()
            targetGlucose = min(200, targetGlucose * noisyCGMTargetMultiplier).jsRounded()
            maxGlucose = min(200, maxGlucose * noisyCGMTargetMultiplier).jsRounded()
        }

        // Calculate threshold: minGlucose thresholds: 80->60, 90->65, etc.
        var threshold = minGlucose - 0.5 * (minGlucose - 40)
        threshold = min(max(profile.thresholdSetting, threshold, 60), 120)

        return (AdjustedGlucoseTargets(minGlucose: minGlucose, maxGlucose: maxGlucose, targetGlucose: targetGlucose), threshold)
    }

    static func buildGlucoseImpactSeries(
        iobDataSeries: [IobResult],
        sensitivity: Decimal,
        withZeroTemp: Bool = false
    ) -> [Decimal] {
        // FIXME: this is assuming 5min steps...
        // Activity is U/hr
        if withZeroTemp {
            return iobDataSeries.map { -$0.iobWithZeroTemp.activity * sensitivity * 5 }
        } else {
            return iobDataSeries.map { -$0.activity * sensitivity * 5 }
        }
    }
}

extension Profile {
    /// This function calculates the `profileTarget` variable from Javascript's determineBasal function
    /// including the adjustments for overrides
    func profileTarget(trioCustomOrefVariables: TrioCustomOrefVariables) -> Decimal? {
        let overrideTarget = trioCustomOrefVariables.overrideTarget
        if overrideTarget != 0, overrideTarget != 6, trioCustomOrefVariables
            .useOverride, !(temptargetSet ?? false)
        {
            return overrideTarget
        }

        return minBg
    }

    /// Calculates the profile ISF at this point in time and applies any overrides to it
    /// This is `sensitivity` in JS
    func profileSensitivity(at: Date, trioCustomOrefVaribales: TrioCustomOrefVariables) -> Decimal {
        let sensitivity = sens ?? sensitivityFor(time: at)
        return trioCustomOrefVaribales.override(sensitivity: sensitivity)
    }
}

extension TrioCustomOrefVariables {
    func overrideFactor() -> Decimal {
        guard useOverride else { return 1 }
        return overridePercentage / 100
    }

    func override(sensitivity: Decimal) -> Decimal {
        if useOverride {
            let overrideFactor = overridePercentage / 100
            if isfAndCr || isf {
                return sensitivity / overrideFactor
            } else {
                return sensitivity
            }
        } else {
            return sensitivity
        }
    }
}

extension Date {
    /// Formats date like JavaScript's Date.toString()
    /// Example: "Sat Nov 22 2025 14:22:58 GMT-0700 (Mountain Standard Time)"
    func jsDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let dateString = formatter.string(from: self)

        // Get GMT offset string like "GMT-0700"
        let seconds = TimeZone.current.secondsFromGMT(for: self)
        let hours = abs(seconds) / 3600
        let minutes = (abs(seconds) % 3600) / 60
        let sign = seconds >= 0 ? "+" : "-"
        let gmtOffset = String(format: "GMT%@%02d%02d", sign, hours, minutes)

        // Get timezone name like "Mountain Standard Time" or "Mountain Daylight Time"
        let style: TimeZone.NameStyle = TimeZone.current.isDaylightSavingTime(for: self) ? .daylightSaving : .standard
        let timezoneName = TimeZone.current.localizedName(for: style, locale: Locale(identifier: "en_US")) ?? TimeZone.current
            .identifier

        return "\(dateString) \(gmtOffset) (\(timezoneName))"
    }
}
