import Foundation

extension DeterminationGenerator {
    static func calculateExpectedDelta(
        targetGlucose: Decimal,
        eventualGlucose: Decimal,
        glucoseImpact: Decimal
    ) -> Decimal {
        // JS expects glucose to rise/fall at rate of glucose impact
        // adjusted by the rate at which glucose would need to rise/fall
        // to move eventual glucose to target over a 2 hr window
        // TODO: expects that glucose can only be available in 5min chunks. do we need to change this handling?

        let fiveMinuteBlocks = (2 * 60) / 5
        let delta = targetGlucose - eventualGlucose
        return (glucoseImpact + Decimal(Int(delta) / fiveMinuteBlocks)).rounded(toPlaces: 1)
    }

    /// Determines whether SMBs are enabled based on profile settings,
    /// computed meal data, CGM conditions, and any active overrides.
    ///
    /// Mirrors the JavaScript oref's `enable_smb()` logic.
    ///
    /// - Parameters:
    ///   - glucose: The latest blood glucose reading.
    ///   - profile: The user profile containing SMB preferences and temp-target flags.
    ///   - autosens: The autosens data (not used in this logic).
    ///   - mealData: Computed carbs-on-board and related meal information.
    ///   - override: An optional override controlling SMB scheduling and hard-off flags.
    ///   - shouldProtectDueToHIGH: `true` if CGM indicates a HIGH reading requiring SMB disable.
    ///   - currentTime: The current system time for scheduled-off evaluation.
    /// - Returns: `true` if SMBs should be enabled, `false` otherwise.
    static func isSMBEnabled(
        glucose: BloodGlucose,
        profile: Profile,
        autosens _: Autosens,
        mealData: ComputedCarbs?,
        override: Override?,
        shouldProtectDueToHIGH: Bool,
        currentTime: Date
    ) -> Bool {
        if let override = override {
            if override.smbIsScheduledOff {
                let startHour = override.start
                let endHour = override.end
                let hour = Calendar.current.component(.hour, from: currentTime)

                // disable SMB during the scheduled-off window [start, end)
                if startHour < endHour {
                    if hour >= Int(startHour), hour < Int(endHour) {
                        return false
                    }
                }
                // disable SMB if window wraps midnight
                else if startHour > endHour {
                    if hour >= Int(startHour) || hour < Int(endHour) {
                        return false
                    }
                }
                // special cases: off all day or single-hour off
                else {
                    if startHour == 0, endHour == 0 {
                        return false
                    }
                    if hour == Int(startHour) {
                        return false
                    }
                }
            } else if override.smbIsOff {
                // hard-off override disables SMB entirely
                return false
            }
        }

        if let hasActiveTempTarget = profile.temptargetSet, hasActiveTempTarget {
            // disable SMB when a high temp target is active and not allowed
            if !profile.allowSMBWithHighTemptarget,
               let targetGlucose = profile.targetBg,
               targetGlucose > 100
            {
                return false
            }

            // enable SMB when a low temp target is active
            if profile.enableSMBWithTemptarget,
               let targetGlucose = profile.targetBg,
               targetGlucose < 100
            {
                return true
            }
        }

        // disable SMB for invalid CGM readings (HIGH)
        if shouldProtectDueToHIGH {
            return false
        }

        // enable SMB unconditionally if always-on preference is set
        if profile.enableSMBAlways {
            return true
        }

        // enable SMB when carbs-on-board (COB) exists
        if profile.enableSMBWithCOB,
           let cob = mealData?.mealCOB,
           cob > 0
        {
            return true
        }

        // enable SMB for the full post-carb window
        if profile.enableSMBAfterCarbs,
           let carbs = mealData?.carbs,
           carbs > 0
        {
            return true
        }

        // enable SMB when BG exceeds the high-BG threshold
        if profile.enableSMBHighBg,
           let glucoseVal = glucose.glucose ?? glucose.sgv,
           glucoseVal >= Int(profile.enableSMBHighBgTarget)
        {
            return true
        }

        // no enable condition met → disable SMB
        return false
    }
    
    static func calculateSensitivityRatio(
        profile: Profile,
        autosens: Autosens?,
        targetGlucose: Decimal,
        temptargetSet: Bool
    ) -> Decimal {
        let normalTarget: Decimal = 100
        let halfBasalTarget = profile.halfBasalExerciseTarget
        var ratio: Decimal = 1

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
            ratio = min(ratio, profile.autosensMax)
            // You can round here if needed: ratio = ratio.rounded(2)
            return ratio
        }
        // Use autosens if present
        if let autosens = autosens {
            return autosens.ratio
        }
        // Otherwise default to 1.0 (no adjustment)
        return 1.0
    }

    static func computeAdjustedBasal(currentBasalRate: Decimal, sensitivityRatio: Decimal) -> Decimal {
        // FIXME: Ideally, we round this here to allowed pump basal increments
        currentBasalRate * sensitivityRatio
    }

    static func computeAdjustedSensitivity(sensitivity: Decimal, sensitivityRatio: Decimal) -> Decimal {
        guard sensitivityRatio != 1.0 else { return sensitivity }
        return (sensitivity / sensitivityRatio).rounded(toPlaces: 1)
    }

    static func checkCurrentTempBasalRateSafety(
        currentTemp: TempBasal,
        lastTempTarget: IobResult.LastTemp?,
        currentTime: Date
    ) -> Bool {
        guard let lastTemp = lastTempTarget, let lastTempDate = lastTemp.timestamp,
              let lastTempDuration = lastTemp.duration else { return true }
        // TODO: throw error for malformed IobResult? Can this be malformed?

        let lastTempAge = Int(currentTime.timeIntervalSince(lastTempDate) / 60) // in minutes
        let tempModulus = Int(lastTempAge + currentTemp.duration) % 30

        if currentTemp.rate != lastTemp.rate, lastTempAge > 10, currentTemp.duration > 0 {
            // Rates don’t match and temp is old: cancel temp
            return false
        }
        let lastTempEnded = lastTempAge - Int(lastTempDuration) // TODO: check if this comes in minutes

        if lastTempEnded > 5, lastTempAge > 10 {
            // Last temp ended long ago but temp is running: cancel temp
            return false
        }

        return true
    }

    /// Adjust glucose targets (min, max, target) based on autosens and/or noise.
    /// - Returns: adjusted targets and new threshold
    static func adjustGlucoseTargets(
        profile: Profile,
        autosens: Autosens?,
        temptargetSet: Bool,
        targetGlucose: Decimal,
        minGlucose: Decimal,
        maxGlucose: Decimal,
        noise: Int
    ) -> (targets: AdjustedGlucoseTargets, threshold: Decimal) {
        var minGlucose = minGlucose
        var maxGlucose = maxGlucose
        var targetGlucose = targetGlucose

        // Only adjust glucose targets for autosens if no temp target set
        if !temptargetSet, let autosens = autosens {
            if (profile.sensitivityRaisesTarget && autosens.ratio < 1) ||
                (profile.resistanceLowersTarget && autosens.ratio > 1)
            {
                minGlucose = ((minGlucose - 60) / autosens.ratio + 60).rounded(toPlaces: 0)
                maxGlucose = ((maxGlucose - 60) / autosens.ratio + 60).rounded(toPlaces: 0)
                targetGlucose = max(80, ((targetGlucose - 60) / autosens.ratio + 60).rounded(toPlaces: 0))
            }
        }

        // Raise target for noisy/CGM data
        if noise >= 2 {
            let noisyCGMTargetMultiplier = max(1.1, profile.noisyCGMTargetMultiplier)
            minGlucose = min(200, minGlucose * noisyCGMTargetMultiplier).rounded(toPlaces: 0)
            targetGlucose = min(200, targetGlucose * noisyCGMTargetMultiplier).rounded(toPlaces: 0)
            maxGlucose = min(200, maxGlucose * noisyCGMTargetMultiplier).rounded(toPlaces: 0)
        }

        // Calculate threshold: minGlucose thresholds: 80->60, 90->65, etc.
        var threshold = minGlucose - 0.5 * (minGlucose - 40)
        threshold = min(max(profile.thresholdSetting, threshold, 60), 120)
        threshold = threshold.rounded(toPlaces: 0)

        return (AdjustedGlucoseTargets(minGlucose: minGlucose, maxGlucose: maxGlucose, targetGlucose: targetGlucose), threshold)
    }

    static func buildGlucoseImpactSeries(iobDataSeries: [IobResult], sensitivity: Decimal) -> [Decimal] {
        iobDataSeries.map { iob in
            // FIXME: this is assuming 5min steps...
            // Activity is U/hr
            // oref0 uses: -activity * ISF * 5
            -iob.activity * sensitivity * 5
        }
    }
}
