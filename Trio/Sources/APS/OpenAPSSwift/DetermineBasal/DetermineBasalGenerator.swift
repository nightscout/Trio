import Foundation

protocol OverrideHandler {
    func overrideProfileParameters(profile: Profile, override: Override?) throws -> Profile

    // TODO: handle mutation of profile parameters that the user can alter using Overrides
    /// This could also possibly be handled via an extension of our existing `ProfileGenerator` (?)
}

enum DeterminationGenerator {
    // override data can just be fetched from the DB
    // handling via overrideManager ?

    /// Top-level determination generator, callers should use this function
    static func generate(
        profile: Profile,
        preferences: Preferences,
        currentTemp: TempBasal,
        iobData: [IobResult],
        mealData: ComputedCarbs,
        autosensData: Autosens,
        reservoirData: Decimal,
        glucose: [BloodGlucose],
        microBolusAllowed: Bool,
        trioCustomOrefVariables: TrioCustomOrefVariables,
        currentTime: Date
    ) throws -> Determination? {
        let glucoseStatus = try Self.getGlucoseStatus(glucoseReadings: glucose)
        guard let glucoseStatus = glucoseStatus else { throw DeterminationError.missingInputs }
        return try determineBasal(
            profile: profile,
            preferences: preferences,
            currentTemp: currentTemp,
            iobData: iobData,
            mealData: mealData,
            autosensData: autosensData,
            reservoirData: reservoirData,
            glucoseStatus: glucoseStatus,
            microBolusAllowed: microBolusAllowed,
            trioCustomOrefVariables: trioCustomOrefVariables,
            currentTime: currentTime
        )
    }

    /// Internal function to implement the core determine basal logic. We have a separate function
    /// from `generate` so that we can pass GlucoseStatus values directly into the function
    /// for testing.
    static func determineBasal(
        profile: Profile,
        preferences: Preferences,
        currentTemp: TempBasal,
        iobData: [IobResult],
        mealData: ComputedCarbs,
        autosensData: Autosens,
        reservoirData _: Decimal,
        glucoseStatus: GlucoseStatus,
        microBolusAllowed: Bool,
        trioCustomOrefVariables: TrioCustomOrefVariables,
        currentTime: Date
    ) throws -> Determination? {
        var autosensData = autosensData

        try checkDeterminationInputs(
            glucoseStatus: glucoseStatus,
            currentTemp: currentTemp,
            iobData: iobData,
            profile: profile,
            trioCustomOrefVariables: trioCustomOrefVariables
        )

        let currentGlucose: Decimal = glucoseStatus.glucose

        if let errorDetermination = try handleTempBasalCases(
            glucoseStatus: glucoseStatus,
            profile: profile,
            currentTemp: currentTemp,
            currentTime: currentTime,
            trioCustomOrefVariables: trioCustomOrefVariables
        ) {
            return errorDetermination
        }

        // Safety check: current temp vs. last temp in iob
        guard let lastTempTarget = iobData.first?.lastTemp else {
            throw DeterminationError.missingIob
        }
        if let reason = checkCurrentTempBasalRateSafety(
            currentTemp: currentTemp,
            lastTempTarget: lastTempTarget,
            currentTime: currentTime
        ) {
            return Determination(
                id: UUID(),
                reason: reason,
                units: nil,
                insulinReq: nil,
                eventualBG: nil,
                sensitivityRatio: nil,
                rate: 0,
                duration: 0,
                iob: nil,
                cob: nil,
                predictions: nil,
                deliverAt: currentTime,
                carbsReq: nil,
                temp: .absolute,
                bg: nil,
                reservoir: nil,
                isf: nil,
                timestamp: nil,
                tdd: nil,
                current_target: nil,
                minDelta: nil,
                expectedDelta: nil,
                minGuardBG: nil,
                minPredBG: nil,
                threshold: nil,
                carbRatio: nil,
                received: false
            )
        }

        let dynamicIsfResult = DynamicISF.calculate(
            profile: profile,
            preferences: preferences,
            currentGlucose: currentGlucose,
            trioCustomOrefVariables: trioCustomOrefVariables
        )

        if let dynamicIsfResult = dynamicIsfResult {
            autosensData = Autosens(
                ratio: dynamicIsfResult.ratio,
                newisf: autosensData.newisf,
                deviationsUnsorted: autosensData.deviationsUnsorted,
                timestamp: autosensData.timestamp
            )
        }
        let (sensitivityRatio, updateAutosensRatio) = calculateSensitivityRatio(
            currentGlucose: currentGlucose,
            profile: profile,
            autosens: autosensData,
            targetGlucose: profile.profileTarget(trioCustomOrefVariables: trioCustomOrefVariables) ?? 120,
            temptargetSet: profile.temptargetSet ?? false,
            dynamicIsfResult: dynamicIsfResult
        )
        if updateAutosensRatio {
            autosensData = Autosens(
                ratio: sensitivityRatio,
                newisf: autosensData.newisf,
                deviationsUnsorted: autosensData.deviationsUnsorted,
                timestamp: autosensData.timestamp
            )
        }

        var basal = profile.currentBasal ?? profile.basalFor(time: currentTime)
        basal *= trioCustomOrefVariables.overrideFactor()
        if dynamicIsfResult == nil {
            basal = computeAdjustedBasal(
                profile: profile,
                currentBasalRate: profile.currentBasal ?? profile.basalFor(time: currentTime),
                sensitivityRatio: sensitivityRatio,
                overrideFactor: trioCustomOrefVariables.overrideFactor()
            )
        } else if let dynamicIsfResult = dynamicIsfResult, profile.tddAdjBasal {
            basal = computeAdjustedBasal(
                profile: profile,
                currentBasalRate: profile.currentBasal ?? profile.basalFor(time: currentTime),
                sensitivityRatio: dynamicIsfResult.tddRatio,
                overrideFactor: trioCustomOrefVariables.overrideFactor()
            )
        }

        // this is the `sens` variable in JS, it's the adjusted sensitivity
        let adjustedSensitivity = computeAdjustedSensitivity(
            sensitivity: profile.sens ?? profile.sensitivityFor(time: currentTime),
            sensitivityRatio: sensitivityRatio,
            trioCustomOrefVariables: trioCustomOrefVariables
        )

        let (adjustedGlucoseTargets, threshold) = adjustGlucoseTargets(
            profile: profile,
            autosens: autosensData,
            trioCustomOrefVariables: trioCustomOrefVariables,
            temptargetSet: profile.temptargetSet ?? false,
            targetGlucose: profile.minBg ?? 100,
            minGlucose: profile.minBg ?? 70, // TODO: can we force unwrap?
            maxGlucose: profile.maxBg ?? 180,
            noise: 1
        )

        let glucoseImpactSeries = buildGlucoseImpactSeries(iobDataSeries: iobData, sensitivity: adjustedSensitivity)
        let glucoseImpactSeriesWithZeroTemp = buildGlucoseImpactSeries(
            iobDataSeries: iobData,
            sensitivity: adjustedSensitivity,
            withZeroTemp: true
        )

        guard let currentGlucoseImpact = glucoseImpactSeries.first?.jsRounded(scale: 2) else {
            throw DeterminationError.determinationError
        }

        let minDelta = min(glucoseStatus.delta, glucoseStatus.shortAvgDelta)
        let minAvgDelta = min(glucoseStatus.shortAvgDelta, glucoseStatus.longAvgDelta)
        let longAvgDelta = glucoseStatus.longAvgDelta

        let intervals: Decimal = 6 // 30 / 5

        var deviation = (intervals * (minDelta - currentGlucoseImpact)).jsRounded()
        if deviation < 0 {
            deviation = (intervals * (minAvgDelta - currentGlucoseImpact)).jsRounded()
            if deviation < 0 {
                deviation = (intervals * (longAvgDelta - currentGlucoseImpact)).jsRounded()
            }
        }

        // Calculate what oref calls "naive eventual glucose"
        guard let currentIob = iobData.first?.iob else {
            throw DeterminationError.missingIob
        }

        let naiveEventualGlucose: Decimal
        if currentIob > 0 {
            naiveEventualGlucose = (currentGlucose - (currentIob * adjustedSensitivity)).jsRounded()
        } else {
            naiveEventualGlucose =
                (
                    currentGlucose -
                        (
                            currentIob *
                                min(
                                    profile.profileSensitivity(at: currentTime, trioCustomOrefVaribales: trioCustomOrefVariables),

                                    adjustedSensitivity
                                )
                        )
                )
                .jsRounded()
        }

        let eventualGlucose = naiveEventualGlucose + deviation

        // Safety: if we ever get an invalid Decimal (very rare with Decimal), handle
        guard eventualGlucose.isFinite else {
            throw DeterminationError.eventualGlucoseCalculationError(sensitivity: adjustedSensitivity, deviation: deviation)
        }

        let forecastResult = ForecastGenerator.generate(
            glucose: currentGlucose,
            glucoseStatus: glucoseStatus,
            currentGlucoseImpact: currentGlucoseImpact,
            glucoseImpactSeries: glucoseImpactSeries,
            glucoseImpactSeriesWithZeroTemp: glucoseImpactSeriesWithZeroTemp,
            iobData: iobData,
            mealData: mealData,
            profile: profile,
            preferences: preferences,
            trioCustomOrefVariables: trioCustomOrefVariables,
            dynamicIsfResult: dynamicIsfResult,
            targetGlucose: adjustedGlucoseTargets.targetGlucose,
            adjustedSensitivity: adjustedSensitivity,
            sensitivityRatio: sensitivityRatio,
            naiveEventualGlucose: naiveEventualGlucose,
            eventualGlucose: eventualGlucose,
            threshold: threshold,
            currentTime: currentTime
        )

        // used for pre dosing decision sanity later on
        let expectedDelta = calculateExpectedDelta(
            targetGlucose: adjustedGlucoseTargets.targetGlucose,
            eventualGlucose: eventualGlucose,
            glucoseImpact: currentGlucoseImpact
        )

        // Build isfReason: "Autosens ratio: X, ISF: Y→Z"
        let originalSensitivity = profile.profileSensitivity(at: currentTime, trioCustomOrefVaribales: trioCustomOrefVariables)
        let isfReason =
            "Autosens ratio: \(sensitivityRatio.jsRounded(scale: 2)), ISF: \(originalSensitivity.jsRounded())→\(adjustedSensitivity.jsRounded())"

        // Build targetLog: "X" or "X→Y" or "X→Y→Z" if target was adjusted
        let profileTarget = profile.profileTarget(trioCustomOrefVariables: trioCustomOrefVariables) ?? 100
        let overrideTarget = trioCustomOrefVariables.overrideTarget
        let targetLog: String
        if adjustedGlucoseTargets.targetGlucose != profileTarget {
            // Include overrideTarget in the middle if it's set and different from final target
            if overrideTarget != 0, overrideTarget != 6, overrideTarget != adjustedGlucoseTargets.targetGlucose {
                targetLog =
                    "\(profileTarget.jsRounded())→\(overrideTarget.jsRounded())→\(adjustedGlucoseTargets.targetGlucose.jsRounded())"
            } else {
                targetLog = "\(profileTarget.jsRounded())→\(adjustedGlucoseTargets.targetGlucose.jsRounded())"
            }
        } else {
            targetLog = "\(adjustedGlucoseTargets.targetGlucose.jsRounded())"
        }

        // Build tddReason: ", Dynamic ISF: On, Sigmoid function, AF: X, Basal ratio: Y, SMB Ratio: Z"
        var tddReason = ""
        if let dynamicIsfResult = dynamicIsfResult {
            tddReason = ", Dynamic ISF: On"
            if preferences.sigmoid {
                tddReason += ", Sigmoid function"
            } else {
                tddReason += ", Logarithmic formula"
            }
            if let limitValue = dynamicIsfResult.limitValue {
                tddReason +=
                    ", Autosens/Dynamic Limit: \(limitValue) (\(dynamicIsfResult.uncappedRatio.jsRounded(scale: 2)))"
            }
            let af = preferences.sigmoid ? preferences.adjustmentFactorSigmoid : preferences.adjustmentFactor
            tddReason += ", AF: \(af)"
            if profile.tddAdjBasal {
                tddReason += ", Basal ratio: \(dynamicIsfResult.tddRatio)"
            }
        }
        // SMB Ratio is added if not default (0.5)
        if profile.smbDeliveryRatio != 0.5 {
            tddReason += ", SMB Ratio: \(min(profile.smbDeliveryRatio, 1))"
        }

        let dosingInputs = DosingEngine.prepareDosingInputs(
            profile: profile,
            mealData: mealData,
            forecast: forecastResult,
            naiveEventualGlucose: naiveEventualGlucose,
            threshold: threshold,
            glucoseImpact: currentGlucoseImpact,
            deviation: deviation,
            currentBasal: profile.currentBasal ?? profile.basalFor(time: currentTime),
            overrideFactor: trioCustomOrefVariables.overrideFactor(),
            adjustedSensitivity: adjustedSensitivity,
            isfReason: isfReason,
            tddReason: tddReason,
            targetLog: targetLog
        )

        let smbDecision = try DosingEngine.makeSMBDosingDecision(
            profile: profile,
            meal: mealData,
            currentGlucose: currentGlucose,
            adjustedTargetGlucose: adjustedGlucoseTargets.targetGlucose,
            minGuardGlucose: forecastResult.minGuardGlucose,
            threshold: threshold,
            glucoseStatus: glucoseStatus,
            trioCustomOrefVariables: trioCustomOrefVariables,
            clock: currentTime
        )

        let smbIsEnabled = smbDecision.isEnabled
        var reason = dosingInputs.reason
        if let smbReason = smbDecision.reason {
            reason += smbReason
        }
        // Add carbs message after smbReason to match JS order
        if let carbsReq = dosingInputs.carbsRequired {
            reason += "\(carbsReq.carbs) add'l carbs req w/in \(carbsReq.minutes)m; "
        }

        var determination = Determination(
            id: UUID(),
            reason: reason,
            units: nil,
            insulinReq: 0,
            eventualBG: Int(forecastResult.eventualGlucose.jsRounded()),
            sensitivityRatio: sensitivityRatio, // this would only the AS-adjusted one for now
            rate: nil,
            duration: nil,
            iob: iobData.first?.iob,
            cob: mealData.mealCOB,
            predictions: Predictions(
                iob: forecastResult.iob.map { Int($0.jsRounded()) },
                zt: forecastResult.zt.map { Int($0.jsRounded()) },
                cob: forecastResult.cob?.map { Int($0.jsRounded()) },
                uam: forecastResult.uam?.map { Int($0.jsRounded()) }
            ),
            deliverAt: currentTime,
            carbsReq: dosingInputs.carbsRequired?.carbs,
            temp: nil,
            bg: currentGlucose,
            reservoir: nil,
            isf: nil,
            timestamp: currentTime,
            tdd: nil,
            current_target: adjustedGlucoseTargets.targetGlucose,
            minDelta: nil,
            expectedDelta: expectedDelta,
            minGuardBG: smbDecision.minGuardGlucose ?? forecastResult.minGuardGlucose,
            minPredBG: forecastResult.minForecastedGlucose,
            threshold: threshold.jsRounded(),
            carbRatio: forecastResult.adjustedCarbRatio.jsRounded(scale: 1),
            received: false
        )

        // MARK: - Core dosing logic

        let (shouldSetTempBasalForLowGlucoseSuspend, lowGlucoseSuspendDetermination) = try DosingEngine.lowGlucoseSuspend(
            currentGlucose: currentGlucose,
            minGuardGlucose: forecastResult.minGuardGlucose,
            iob: currentIob,
            minDelta: minDelta,
            expectedDelta: expectedDelta,
            threshold: threshold,
            overrideFactor: trioCustomOrefVariables.overrideFactor(),
            profile: profile,
            adjustedSensitivity: adjustedSensitivity,
            targetGlucose: adjustedGlucoseTargets.targetGlucose,
            currentTemp: currentTemp,
            determination: determination
        )
        determination = lowGlucoseSuspendDetermination
        if shouldSetTempBasalForLowGlucoseSuspend {
            return determination
        }

        let (shouldSetTempBasalForSkipNeutralTemp, skipNeutralTempDetermination) = try DosingEngine.skipNeutralTempBasal(
            smbIsEnabled: smbIsEnabled,
            profile: profile,
            clock: currentTime,
            currentTemp: currentTemp,
            determination: determination
        )
        determination = skipNeutralTempDetermination
        if shouldSetTempBasalForSkipNeutralTemp {
            return determination
        }

        let (shouldSetTempBasalForLowEventualGlucose, lowEventualGlucoseDetermination) = try DosingEngine
            .handleLowEventualGlucose(
                eventualGlucose: forecastResult.eventualGlucose,
                minGlucose: adjustedGlucoseTargets.minGlucose,
                targetGlucose: adjustedGlucoseTargets.targetGlucose,
                minDelta: minDelta,
                expectedDelta: expectedDelta,
                carbsRequired: dosingInputs.rawCarbsRequired,
                naiveEventualGlucose: naiveEventualGlucose,
                glucoseStatus: glucoseStatus,
                currentTemp: currentTemp,
                basal: basal,
                profile: profile,
                determination: determination,
                adjustedSensitivity: adjustedSensitivity,
                overrideFactor: trioCustomOrefVariables.overrideFactor()
            )
        determination = lowEventualGlucoseDetermination
        if shouldSetTempBasalForLowEventualGlucose {
            return determination
        }

        let (
            shouldSetTempBasalForGlucoseFallingFasterThanExpected,
            glucoseFallingFasterThanExpectedDetermination
        ) = try DosingEngine.glucoseFallingFasterThanExpected(
            eventualGlucose: forecastResult.eventualGlucose,
            minGlucose: adjustedGlucoseTargets.minGlucose,
            minDelta: minDelta,
            expectedDelta: expectedDelta,
            glucoseStatus: glucoseStatus,
            currentTemp: currentTemp,
            basal: basal,
            smbIsEnabled: smbIsEnabled,
            profile: profile,
            determination: determination
        )
        determination = glucoseFallingFasterThanExpectedDetermination
        if shouldSetTempBasalForGlucoseFallingFasterThanExpected {
            return determination
        }

        let (
            shouldSetTempBasalEventualOrForecastGlucoseLessThanMax,
            eventualOrForecastGlucoseLessThanMaxDetermination
        ) = try DosingEngine.eventualOrForecastGlucoseLessThanMax(
            eventualGlucose: forecastResult.eventualGlucose,
            maxGlucose: adjustedGlucoseTargets.maxGlucose,
            minForecastGlucose: forecastResult.minForecastedGlucose,
            currentTemp: currentTemp,
            basal: basal,
            smbIsEnabled: smbIsEnabled,
            profile: profile,
            determination: determination
        )
        determination = eventualOrForecastGlucoseLessThanMaxDetermination
        if shouldSetTempBasalEventualOrForecastGlucoseLessThanMax {
            return determination
        }

        if forecastResult.eventualGlucose >= adjustedGlucoseTargets.maxGlucose {
            determination
                .reason +=
                "Eventual BG \(DosingEngine.convertGlucose(profile: profile, glucose: forecastResult.eventualGlucose)) >= \(DosingEngine.convertGlucose(profile: profile, glucose: adjustedGlucoseTargets.maxGlucose)), "
        }

        let (shouldSetTempBasalForIobGreaterThanMax, iobGreaterThanMaxDetermination) = try DosingEngine.iobGreaterThanMax(
            iob: currentIob,
            maxIob: profile.maxIob,
            currentTemp: currentTemp,
            basal: basal,
            profile: profile,
            determination: determination
        )
        determination = iobGreaterThanMaxDetermination
        if shouldSetTempBasalForIobGreaterThanMax {
            return determination
        }

        // MARK: - Aggressive dosing logic (SMB, High Temps)

        // Calculate Insulin Required
        let (insulinRequired, insulinReqDetermination) = DosingEngine.calculateInsulinRequired(
            minForecastGlucose: forecastResult.minForecastedGlucose,
            eventualGlucose: forecastResult.eventualGlucose,
            targetGlucose: adjustedGlucoseTargets.targetGlucose,
            adjustedSensitivity: adjustedSensitivity,
            maxIob: profile.maxIob,
            currentIob: currentIob,
            determination: determination
        )
        determination = insulinReqDetermination

        // SMB Delivery
        let (shouldSetTempBasalForSMB, smbDetermination) = try DosingEngine.determineSMBDelivery(
            insulinRequired: insulinRequired,
            microBolusAllowed: microBolusAllowed,
            smbIsEnabled: smbIsEnabled,
            currentGlucose: currentGlucose,
            threshold: threshold,
            profile: profile,
            trioCustomOrefVariables: trioCustomOrefVariables,
            mealData: mealData,
            iobData: iobData,
            currentTime: currentTime,
            targetGlucose: adjustedGlucoseTargets.targetGlucose,
            naiveEventualGlucose: naiveEventualGlucose,
            minIOBForecastedGlucose: forecastResult.minIOBForecastedGlucose,
            adjustedSensitivity: adjustedSensitivity,
            adjustedCarbRatio: forecastResult.adjustedCarbRatio,
            basal: basal,
            determination: determination
        )
        determination = smbDetermination
        if shouldSetTempBasalForSMB {
            return determination
        }

        // High Temp Basal (Fallback)
        return try DosingEngine.determineHighTempBasal(
            insulinRequired: insulinRequired,
            basal: basal,
            profile: profile,
            currentTemp: currentTemp,
            determination: determination
        )
    }

    static func checkDeterminationInputs(
        glucoseStatus: GlucoseStatus?,
        currentTemp _: TempBasal?,
        iobData: [IobResult]?,
        profile: Profile?,
        trioCustomOrefVariables: TrioCustomOrefVariables
    ) throws {
        guard let glucoseStatus = glucoseStatus else {
            throw DeterminationError.missingGlucoseStatus
        }
        guard let profile = profile else {
            throw DeterminationError.missingProfile
        }
        guard profile.profileTarget(trioCustomOrefVariables: trioCustomOrefVariables) != nil else {
            throw DeterminationError.invalidProfileTarget
        }
        // we have to allow 38 values so that we can cancel high temps
        if glucoseStatus.glucose < 38 || glucoseStatus.glucose > 600 {
            throw DeterminationError.glucoseOutOfRange(glucose: glucoseStatus.glucose)
        }
        guard let _ = iobData else {
            throw DeterminationError.missingIob
        }
    }

    static func handleTempBasalCases(
        glucoseStatus: GlucoseStatus,
        profile: Profile,
        currentTemp: TempBasal?,
        currentTime: Date,
        trioCustomOrefVariables: TrioCustomOrefVariables
    ) throws -> Determination? {
        let glucose = glucoseStatus.glucose
        let noise = glucoseStatus.noise
        let bgTime = glucoseStatus.date
        let minAgo = Decimal(currentTime.timeIntervalSince(bgTime) / 60) // minutes
        let shortAvgDelta = glucoseStatus.shortAvgDelta
        let longAvgDelta = glucoseStatus.longAvgDelta
        let delta = glucoseStatus.delta
        let device = glucoseStatus.device

        // Always use profile-supplied basal
        guard let profileBasal = profile.currentBasal else {
            throw DeterminationError.missingCurrentBasal
        }
        let basal = profileBasal * trioCustomOrefVariables.overrideFactor()

        // Compose tick for log
        let tick: String = (delta > -0.5) ? "+\(delta.rounded(toPlaces: 0))" : "\(delta.rounded(toPlaces: 0))"
        let minDelta = min(delta, shortAvgDelta)
        let minAvgDelta = min(shortAvgDelta, longAvgDelta)
        let maxDelta = max(delta, shortAvgDelta, longAvgDelta)

        var reason = ""

        // === ERROR CONDITIONS ===
        // xDrip code 38 = sensor error; BG <= 10 = ???/calibrating; noise >= 3 = high noise
        if glucose <= 10 || glucose == 38 || noise >= 3 {
            reason = "CGM is calibrating, in ??? state, or noise is high"
        }
        // minAgo (BG age) > 12 or < -5 = old/future BG - can overwrite calibration reason (matches JS)
        if minAgo > 12 || minAgo < -5 {
            reason =
                "If current system time \(currentTime.jsDateString()) is correct, then BG data is too old. The last BG data was read \(minAgo.jsRounded(scale: 1))m ago at \(bgTime.jsDateString())"
        } else if shortAvgDelta == 0 && longAvgDelta == 0 {
            // CGM data unchanged (flat) - only checked if BG is not too old
            if glucoseStatus.lastCalIndex != nil, glucoseStatus.lastCalIndex! < 3 {
                reason = "CGM was just calibrated"
            } else {
                reason =
                    "CGM data is unchanged (\(glucose)+\(delta)) for 5m w/ \(shortAvgDelta) mg/dL ~15m change & \(longAvgDelta) mg/dL ~45m change"
            }
        }

        let errorDetected =
            glucose <= 10 ||
            glucose == 38 ||
            noise >= 3 ||
            minAgo > 12 ||
            minAgo < -5

        // === IF ERROR, CANCEL/SHORTEN TEMPS ===
        guard errorDetected, let currentTemp = currentTemp else { return nil }

        if currentTemp.rate >= basal { // high temp is running
            // Replace high temp with neutral temp at scheduled basal rate for 30min
            let reasonWithAction = reason +
                ". Replacing high temp basal of \(currentTemp.rate) with neutral temp of \(basal)"
            return Determination(
                id: UUID(),
                reason: reasonWithAction,
                units: nil,
                insulinReq: nil,
                eventualBG: nil,
                sensitivityRatio: nil,
                rate: basal,
                duration: 30,
                iob: nil,
                cob: nil,
                predictions: nil,
                deliverAt: currentTime,
                carbsReq: nil,
                temp: .absolute,
                bg: nil,
                reservoir: nil,
                isf: profile.sens,
                timestamp: currentTime,
                tdd: nil,
                current_target: nil,
                minDelta: minDelta,
                expectedDelta: nil,
                minGuardBG: nil,
                minPredBG: nil,
                threshold: nil,
                carbRatio: nil,
                received: false
            )
        } else if currentTemp.rate == 0, currentTemp.duration > 30 {
            // Shorten long zero temp to 30m
            let reasonWithAction = reason + ". Shortening \(currentTemp.duration)m long zero temp to 30m. "
            return Determination(
                id: UUID(),
                reason: reasonWithAction,
                units: nil,
                insulinReq: nil,
                eventualBG: nil,
                sensitivityRatio: nil,
                rate: 0,
                duration: 30,
                iob: nil,
                cob: nil,
                predictions: nil,
                deliverAt: currentTime,
                carbsReq: nil,
                temp: .absolute,
                bg: nil,
                reservoir: nil,
                isf: profile.sens,
                timestamp: currentTime,
                tdd: nil,
                current_target: nil,
                minDelta: minDelta,
                expectedDelta: nil,
                minGuardBG: nil,
                minPredBG: nil,
                threshold: nil,
                carbRatio: nil,
                received: false
            )
        } else {
            // Do nothing (temp already safe)
            let reasonWithAction = reason + ". Temp \(currentTemp.rate) <= current basal \(basal)U/hr; doing nothing. "
            return Determination(
                id: UUID(),
                reason: reasonWithAction,
                units: nil,
                insulinReq: nil,
                eventualBG: nil,
                sensitivityRatio: nil,
                rate: nil,
                duration: nil,
                iob: nil,
                cob: nil,
                predictions: nil,
                deliverAt: nil,
                carbsReq: nil,
                temp: currentTemp.temp,
                bg: nil,
                reservoir: nil,
                isf: profile.sens,
                timestamp: currentTime,
                tdd: nil,
                current_target: nil,
                minDelta: minDelta,
                expectedDelta: nil,
                minGuardBG: nil,
                minPredBG: nil,
                threshold: nil,
                carbRatio: nil,
                received: false
            )
        }
    }
}
