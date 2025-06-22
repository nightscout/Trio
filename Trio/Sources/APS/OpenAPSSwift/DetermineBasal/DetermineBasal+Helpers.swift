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
}
