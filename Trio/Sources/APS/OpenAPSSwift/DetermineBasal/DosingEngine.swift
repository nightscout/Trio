import Foundation

enum DosingEngine {
    struct DosingInputs {
        let reason: String
        let carbsRequired: (carbs: Decimal, minutes: Decimal)?
    }

    /// struct to keep the relevant state needed for the output of the SMB decision logic
    struct SMBDecision {
        let isEnabled: Bool
        let manualBolusError: Int?
        let minGuardGlucose: Decimal?
        let reason: String?
    }

    /// checks to see if SMB are enabled via the profile
    private static func isProfileSmbEnabled(
        currentGlucose: Decimal,
        adjustedTargetGlucose: Decimal,
        profile: Profile,
        meal: ComputedCarbs,
        trioCustomOrefVariables: TrioCustomOrefVariables,
        clock: Date
    ) throws -> Bool {
        if trioCustomOrefVariables.smbIsOff {
            return false
        }

        if try isSmbScheduledOff(trioCustomOrefVariables: trioCustomOrefVariables, clock: clock) {
            return false
        }

        if trioCustomOrefVariables.shouldProtectDueToHIGH {
            return false
        }

        if !profile.allowSMBWithHighTemptarget, profile.temptargetSet == true, adjustedTargetGlucose > 100 {
            return false
        }

        if profile.enableSMBAlways {
            return true
        }

        if profile.enableSMBWithCOB, meal.mealCOB > 0 {
            return true
        }

        if profile.enableSMBAfterCarbs, meal.carbs > 0 {
            return true
        }

        if profile.enableSMBWithTemptarget, profile.temptargetSet == true, adjustedTargetGlucose < 100 {
            return true
        }

        if profile.enableSMBHighBg, currentGlucose >= profile.enableSMBHighBgTarget {
            return true
        }

        return false
    }

    /// helper function to check if SMB is scheduled off given the current timezone
    private static func isSmbScheduledOff(trioCustomOrefVariables: TrioCustomOrefVariables, clock: Date) throws -> Bool {
        guard trioCustomOrefVariables.smbIsScheduledOff else {
            return false
        }

        guard let currentHour = clock.hourInLocalTime.map({ Decimal($0) }) else {
            throw CalendarError.invalidCalendarHourOnly
        }
        let startHour = trioCustomOrefVariables.start
        let endHour = trioCustomOrefVariables.end

        // SMBs will be disabled from [start, end) local time
        if startHour < endHour, currentHour >= startHour && currentHour < endHour {
            // disable when the schedule does not wrap around midnight
            return true
        } else if startHour > endHour, currentHour >= startHour || currentHour < endHour {
            // disable when the schedule does wrap around midnight
            return true
        } else if startHour == 0, endHour == 0 {
            // schedule specifies the entire day
            return true
        } else if startHour == endHour, currentHour == startHour {
            // one hour of scheduled off SMB
            return true
        }

        return false
    }

    /// helper function for reason string glucose output
    private static func convertGlucose(profile: Profile, glucose: Decimal) -> Decimal {
        let units = profile.outUnits ?? .mgdL
        switch units {
        case .mgdL: return glucose.jsRounded()
        case .mmolL: return glucose.asMmolL
        }
    }

    /// Top level smb enabling logic
    ///
    /// This function includes both the profile / customOrefVariable checks from JS `enable_smb` as
    /// well as some of the later checks from `determineBasal` that can disable SMB
    static func makeSMBDosingDecision(
        profile: Profile,
        meal: ComputedCarbs,
        currentGlucose: Decimal,
        adjustedTargetGlucose: Decimal,
        adjustedSensitivity _: Decimal,
        minGuardGlucose: Decimal,
        eventualGlucose _: Decimal,
        threshold: Decimal,
        glucoseStatus: GlucoseStatus,
        trioCustomOrefVariables: TrioCustomOrefVariables,
        clock: Date
    ) throws -> SMBDecision {
        var smbIsEnabled = try isProfileSmbEnabled(
            currentGlucose: currentGlucose,
            adjustedTargetGlucose: adjustedTargetGlucose,
            profile: profile,
            meal: meal,
            trioCustomOrefVariables: trioCustomOrefVariables,
            clock: clock
        )

        // these last two checks are implemented outside of the core enable_smb
        // function in JS but we should keep all of the smb enabling logic
        // in one place. Note: We can't shortcut the return value because
        // the determineBasal logic always evaluates this logic
        var manualBolusError: Int?
        var minGuardGlucoseDecision: Decimal?
        var reason: String?
        if smbIsEnabled, minGuardGlucose < threshold {
            manualBolusError = 1
            minGuardGlucoseDecision = minGuardGlucose
            smbIsEnabled = false
        }

        let maxDeltaGlucoseThreshold = min(profile.maxDeltaBgThreshold, 0.4)
        if glucoseStatus.maxDelta > maxDeltaGlucoseThreshold * currentGlucose {
            reason =
                "maxDelta \(convertGlucose(profile: profile, glucose: glucoseStatus.maxDelta)) > \(100 * maxDeltaGlucoseThreshold)% of BG \(convertGlucose(profile: profile, glucose: currentGlucose)) - SMB disabled!, "
            smbIsEnabled = false
        }

        return SMBDecision(
            isEnabled: smbIsEnabled,
            manualBolusError: manualBolusError,
            minGuardGlucose: minGuardGlucoseDecision,
            reason: reason
        )
    }

    static func prepareDosingInputs(
        profile: Profile,
        mealData: ComputedCarbs,
        forecast: ForecastResult,
        naiveEventualGlucose: Decimal,
        threshold: Decimal,
        glucoseImpact: Decimal,
        deviation: Decimal,
        currentBasal: Decimal,
        overrideFactor: Decimal,
        adjustedSensitivity: Decimal,
        isfReason: String,
        tddReason: String,
        targetLog: String // This is a pre-formatted string from the JS
    ) -> DosingInputs {
        let lastIOBpredBG = forecast.iob.last ?? 0
        let lastCOBpredBG = forecast.cob?.last
        let lastUAMpredBG = forecast.uam?.last

        var reason =
            "\(isfReason), COB: \(mealData.mealCOB), Dev: \(deviation), BGI: \(glucoseImpact), CR: \(forecast.adjustedCarbRatio), Target: \(targetLog), minPredBG \(forecast.minForecastedGlucose), minGuardBG \(forecast.minGuardGlucose), IOBpredBG \(lastIOBpredBG)"

        if let lastCOB = lastCOBpredBG {
            reason += ", COBpredBG \(lastCOB)"
        }
        if let lastUAM = lastUAMpredBG {
            reason += ", UAMpredBG \(lastUAM)"
        }
        reason += tddReason
        reason += "; " // Start of conclusion

        let carbsRequiredResult = calculateCarbsRequired(
            profile: profile,
            mealData: mealData,
            naiveEventualGlucose: naiveEventualGlucose,
            minGuardGlucose: forecast.minGuardGlucose,
            threshold: threshold,
            iobForecast: forecast.iob,
            cobForecast: forecast.internalCob,
            carbImpact: forecast.carbImpact,
            remainingCarbImpactPeak: forecast.remainingCarbImpactPeak,
            currentBasal: currentBasal,
            overrideFactor: overrideFactor,
            adjustedSensitivity: adjustedSensitivity,
            adjustedCarbRatio: forecast.adjustedCarbRatio
        )

        if let result = carbsRequiredResult {
            reason += "\(result.carbs) add'l carbs req w/in \(result.minutes)m; "
        }

        return DosingInputs(reason: reason, carbsRequired: carbsRequiredResult)
    }

    /// Calculates the carbohydrates required to avoid a potential hypoglycemic event.
    ///
    /// - Returns: A tuple containing the required carbs and minutes until BG is below threshold, or `nil` if no carbs are required.
    static func calculateCarbsRequired(
        profile: Profile,
        mealData: ComputedCarbs,
        naiveEventualGlucose: Decimal,
        minGuardGlucose: Decimal,
        threshold: Decimal,
        iobForecast: [Decimal],
        cobForecast: [Decimal],
        carbImpact: Decimal,
        remainingCarbImpactPeak: Decimal,
        currentBasal: Decimal,
        overrideFactor: Decimal,
        adjustedSensitivity: Decimal,
        adjustedCarbRatio: Decimal
    ) -> (carbs: Decimal, minutes: Decimal)? {
        var carbsRequiredGlucose = naiveEventualGlucose
        if naiveEventualGlucose < 40 {
            carbsRequiredGlucose = min(minGuardGlucose, naiveEventualGlucose)
        }

        let glucoseUndershoot = threshold - carbsRequiredGlucose

        var minutesAboveThreshold = Decimal(240)

        let useCOBForecast = mealData.mealCOB > 0 && (carbImpact > 0 || remainingCarbImpactPeak > 0)
        let forecast = useCOBForecast ? cobForecast : iobForecast

        // At this point in the JS the forecasts have already been rounded
        for (index, glucose) in forecast.map({ $0.jsRounded() }).enumerated() {
            if glucose < threshold {
                minutesAboveThreshold = Decimal(5) * Decimal(index)
                break
            }
        }

        let zeroTempDuration = minutesAboveThreshold
        let zeroTempEffect = currentBasal * adjustedSensitivity * overrideFactor * zeroTempDuration / 60

        let mealCarbs = mealData.carbs
        let cobForCarbsRequired = max(0, mealData.mealCOB - (Decimal(0.25) * mealCarbs))

        guard adjustedCarbRatio > 0 else { return nil }
        let carbSensitivityFactor = adjustedSensitivity / adjustedCarbRatio
        guard carbSensitivityFactor > 0 else { return nil }

        var carbsRequired = (glucoseUndershoot - zeroTempEffect) / carbSensitivityFactor - cobForCarbsRequired
        carbsRequired = carbsRequired.rounded(toPlaces: 0)

        let carbsRequiredThreshold = profile.carbsReqThreshold
        if carbsRequired >= carbsRequiredThreshold, minutesAboveThreshold <= 45 {
            return (carbs: carbsRequired, minutes: minutesAboveThreshold)
        }

        return nil
    }

    /// Determines if a low glucose suspend is warranted.
    ///
    /// This function checks for low glucose conditions and may modify the determination object
    /// with a suspend recommendation and an updated reason string.
    ///
    /// - Returns: A tuple containing:
    ///   - `setTempBasal`: A `Bool` that is `true` if `determineBasal` should exit and apply the recommendation immediately.
    ///   - `determination`: The (potentially modified) determination object.
    static func lowGlucoseSuspend(
        currentGlucose: Decimal,
        minGuardGlucose: Decimal,
        iob: Decimal,
        minDelta: Decimal,
        expectedDelta: Decimal,
        threshold: Decimal,
        overrideFactor: Decimal,
        profile: Profile,
        eventualGlucose _: Decimal,
        adjustedSensitivity: Decimal,
        targetGlucose: Decimal,
        currentTemp: TempBasal,
        determination: Determination
    ) throws -> (shouldSetTempBasal: Bool, determination: Determination) {
        var newDetermination = determination

        guard let currentBasal = profile.currentBasal else {
            // Should have been checked earlier
            throw TempBasalFunctionError.invalidBasalRateOnProfile
        }

        let suspendThreshold = -currentBasal * overrideFactor * 20 / 60
        if currentGlucose < threshold, iob < suspendThreshold, minDelta > 0, minDelta > expectedDelta {
            let iobString = String(describing: iob)
            let suspendString = String(describing: suspendThreshold.jsRounded(scale: 2))
            let minDeltaString = String(describing: convertGlucose(profile: profile, glucose: minDelta))
            let expectedDeltaString = String(describing: convertGlucose(profile: profile, glucose: expectedDelta))

            newDetermination
                .reason +=
                "IOB \(iobString) < \(suspendString) and minDelta \(minDeltaString) > expectedDelta \(expectedDeltaString); "
            return (shouldSetTempBasal: false, determination: newDetermination)
        } else if currentGlucose < threshold || minGuardGlucose < threshold {
            let minGuardGlucoseString = String(describing: convertGlucose(profile: profile, glucose: minGuardGlucose))
            let thresholdString = String(describing: convertGlucose(profile: profile, glucose: threshold))
            newDetermination.reason += "minGuardBG \(minGuardGlucoseString) < \(thresholdString)"

            let glucoseUndershoot = targetGlucose - minGuardGlucose
            if minGuardGlucose < threshold {
                newDetermination.manualBolusErrorString = 2
                newDetermination.minGuardBG = minGuardGlucose
            }

            let worstCaseInsulinRequired = glucoseUndershoot / adjustedSensitivity
            var durationRequired = (60 * worstCaseInsulinRequired / (currentBasal * overrideFactor)).jsRounded()
            durationRequired = (durationRequired / 30).jsRounded() * 30
            durationRequired = max(30, min(120, durationRequired))

            let finalDetermination = try TempBasalFunctions.setTempBasal(
                rate: 0,
                duration: durationRequired,
                profile: profile,
                determination: newDetermination,
                currentTemp: currentTemp
            )
            return (shouldSetTempBasal: true, determination: finalDetermination)
        }

        return (shouldSetTempBasal: false, determination: determination)
    }

    /// Determines if a neutral temp basal should be skipped to avoid pump alerts.
    ///
    /// - Returns: A tuple containing:
    ///   - `shouldSetTempBasal`: A `Bool` that is `true` if `determineBasal` should exit and apply the recommendation immediately.
    ///   - `determination`: The (potentially modified) determination object.
    static func skipNeutralTempBasal(
        smbIsEnabled: Bool,
        profile: Profile,
        clock: Date,
        currentTemp: TempBasal,
        determination: Determination
    ) throws -> (shouldSetTempBasal: Bool, determination: Determination) {
        guard profile.skipNeutralTemps else {
            return (shouldSetTempBasal: false, determination: determination)
        }
        guard let totalMinutes = clock.minutesSinceMidnight else {
            throw CalendarError.invalidCalendar
        }

        let minute = totalMinutes % 60
        guard minute >= 55 else {
            return (shouldSetTempBasal: false, determination: determination)
        }

        if !smbIsEnabled {
            var newDetermination = determination
            let minutesLeft = 60 - minute
            newDetermination
                .reason +=
                "; Canceling temp at \(minutesLeft)min before turn of the hour to avoid beeping of MDT. SMB are disabled anyways."

            let finalDetermination = try TempBasalFunctions.setTempBasal(
                rate: 0,
                duration: 0,
                profile: profile,
                determination: newDetermination,
                currentTemp: currentTemp
            )
            return (shouldSetTempBasal: true, determination: finalDetermination)
        } else {
            // In the JS, this path logs to the console but does not modify determination.
            // We will do nothing here to match that behavior.
            return (shouldSetTempBasal: false, determination: determination)
        }
    }
}
