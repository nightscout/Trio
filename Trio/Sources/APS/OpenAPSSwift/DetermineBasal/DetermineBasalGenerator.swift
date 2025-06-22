import Foundation

protocol OverrideHandler {
    func overrideProfileParameters(profile: Profile, override: Override?) throws -> Profile

    // TODO: handle mutation of profile parameters that the user can alter using Overrides
    /// This could also possibly be handled via an extension of our existing `ProfileGenerator` (?)
}

enum DeterminationGenerator {
    // override data can just be fetched from the DB
    // handling via overrideManager ?

    static func generate(
        profile: Profile,
        currentTemp: TempBasal,
        iobData: [IobResult],
        mealData: ComputedCarbs,
        autosensData: Autosens,
        reservoirData _: Reservoir,
        glucoseStatus: GlucoseStatus?,
        currentTime: Date
    ) throws -> Determination? {
        try checkDeterminationInputs(
            glucoseStatus: glucoseStatus,
            currentTemp: currentTemp,
            iobData: iobData,
            profile: profile,
            currentTime: currentTime,
        )

        guard let glucoseStatus = glucoseStatus else { throw DeterminationError.missingInputs }

        let currentGlucose: Decimal = glucoseStatus.glucose

        if let errorDetermination = handleTempBasalCases(
            glucoseStatus: glucoseStatus,
            profile: profile,
            currentTemp: currentTemp,
            currentTime: currentTime
        ) {
            return errorDetermination
        }

        let sensitivityRatio = calculateSensitivityRatio(
            profile: profile,
            autosens: autosensData,
            targetGlucose: profile.targetBg ?? 120,
            temptargetSet: profile.temptargetSet ?? false
        )

        let basal = computeAdjustedBasal(
            currentBasalRate: profile.currentBasal ?? profile.basalFor(time: currentTime),
            sensitivityRatio: sensitivityRatio
        )
        let sensitivity = computeAdjustedSensitivity(
            sensitivity: profile.sens ?? profile.sensitivityFor(time: currentTime),
            sensitivityRatio: sensitivityRatio
        )

        // Safety check: current temp vs. last temp in iob
        if !checkCurrentTempBasalRateSafety(
            currentTemp: currentTemp,
            lastTempTarget: iobData[0].lastTemp,
            currentTime: currentTime
        ) {
            let reason =
                "Safety check: currentTemp does not match lastTemp in IOB or lastTemp ended long ago; canceling temp basal."
            return Determination(
                id: UUID(),
                reason: reason,
                units: nil,
                insulinReq: nil,
                eventualBG: nil,
                sensitivityRatio: nil,
                rate: 0,
                duration: 0,
                iob: iobData[0].iob,
                cob: nil,
                predictions: nil,
                deliverAt: currentTime,
                carbsReq: nil,
                temp: .absolute,
                bg: glucoseStatus.glucose,
                reservoir: nil,
                isf: profile.sens,
                timestamp: currentTime,
                tdd: nil,
                current_target: profile.targetBg,
                insulinForManualBolus: nil,
                manualBolusErrorString: nil,
                minDelta: nil,
                expectedDelta: nil,
                minGuardBG: nil,
                minPredBG: nil,
                threshold: nil,
                carbRatio: profile.carbRatio,
                received: false
            )
        }

        let (adjustedGlucoseTargets, threshold) = adjustGlucoseTargets(
            profile: profile,
            autosens: autosensData,
            temptargetSet: profile.temptargetSet ?? false,
            targetGlucose: profile.targetBg ?? 100, // TODO: grab from therapy settings
            minGlucose: profile.minBg ?? 70, // TODO: can we force unwrap?
            maxGlucose: profile.maxBg ?? 180,
            noise: 1
        )

        let glucoseImpactSeries = buildGlucoseImpactSeries(iobDataSeries: iobData, sensitivity: sensitivity)
        let currentGlucoseImpact = glucoseImpactSeries[0]

        let minDelta = min(glucoseStatus.delta, glucoseStatus.shortAvgDelta)
        let minAvgDelta = min(glucoseStatus.shortAvgDelta, glucoseStatus.longAvgDelta)
        let longAvgDelta = glucoseStatus.longAvgDelta

        let intervals: Decimal = 6 // 30 / 5

        var deviation = (intervals * (minDelta - currentGlucoseImpact)).rounded(toPlaces: 0)
        if deviation < 0 {
            deviation = (intervals * (minAvgDelta - currentGlucoseImpact)).rounded(toPlaces: 0)
            if deviation < 0 {
                deviation = (intervals * (longAvgDelta - currentGlucoseImpact)).rounded(toPlaces: 0)
            }
        }

        // Calculate what oref calls "naive eventual glucose"
        let currentIob = iobData[0].iob

        let naiveEventualGlucose: Decimal
        if currentIob > 0 {
            naiveEventualGlucose = (currentGlucose - (currentIob * sensitivity)).rounded(toPlaces: 0)
        } else {
            naiveEventualGlucose =
                (currentGlucose - (currentIob * min(profile.sens ?? profile.sensitivityFor(time: currentTime), sensitivity)))
                    .rounded(toPlaces: 0)
        }

        let eventualGlucose = naiveEventualGlucose + deviation

        // Safety: if we ever get an invalid Decimal (very rare with Decimal), handle
        guard eventualGlucose.isFinite else {
            throw DeterminationError.eventualGlucoseCalculationError(sensitivity: sensitivity, deviation: deviation)
        }

        let forecastGenerator = ForecastGenerator()
        let forecastResult = forecastGenerator.generate(
            glucose: currentGlucose,
            glucoseImpactSeries: glucoseImpactSeries,
            iobData: iobData,
            mealData: mealData,
            profile: profile,
            adjustedSensitivity: sensitivity,
            sensitivityRatio: sensitivityRatio,
            naiveEventualGlucose: naiveEventualGlucose,
            eventualGlucose: eventualGlucose,
            threshold: threshold,
            currentTime: currentTime
        )

        let expectedDelta = calculateExpectedDelta(
            targetGlucose: profile.targetBg ?? 100,
            eventualGlucose: eventualGlucose,
            glucoseImpact: currentGlucoseImpact
        )

        // TODO: STOPPING at LINE 734
        // L734ff handles forecasting, already handled (I hope)
        // continue at ~785

        return nil
        // FIXME: implement... (return type will not be Optional; just to shut up the compiler)

        /// We also need a call to glucose-get-last here (JS passes object `glucoseStatus`) → could be a simple function in GlucoseStorage
        /// We also need the tempBasal helpers (JS passes object `tempBasalFunctions` with functions)
        /// `tempBasalFunctions.getMaxSafeBasal` should be a helper function in or extension of`TrioSettings.swift`
        /// `tempBasalFunctions.setTempBasal` is a helper function utilizing pass by value of `rT` ("requested Temp") and adjusting `rT.duration` and `rT.rate`… can be an extension / helper fn of `DeterminationGenerator` itself
        /// TLDR; we could omit the 2 parameters `glucoseStatus` and `tempBasalFunctions`

        /// OTHER PARAMS:
        ///
        /// JS oref has `reservoir_data`; we have that on file via `loadFileFromStorageAsync(name: Monitor.reservoir)`
        /// NOT NEEDED: `pumphistory` → we no longer calculate TDD in determine
        /// NOT NEEDED: `preferences`, only used for dynamic ISF → pull this out
        /// NOT NEEDED: `basalprofile`, was used for TDD calc as well → remove
        /// NOT NEEDED: `trio_custom_variables` was used for (1) override handling, (2) SMB enabling → we should handle (1) in service of its own, and (2) already outlined via SMBProvider
        /// `microBolusAllowed` is currently HARD-CODED (!) to `true`… we always allow microbolusing and only handle this via the various SMB settings → remove ?

        /// All input params can EITHER be passed directly, OR…
        /// we handle it via an encapsulated struct (I chose DeterminationInputs
        // TODO: Do we want store algorithm input *and* output?

        /// Current determine basal (if we ignore forecasting logic; already modularized) does:
        /// 1. Validate CGM → cancel if needed ✅
        /// 2. Override basal → log ✅
        /// 3. Load targets → error if missing ✅
        /// 4. Adjust sensitivity → maybe adjust basal/target ✅
        /// 5. Check IOB consistency → cancel if needed ✅
        /// 6. Compute deviation/eventualBG → log ✅
        /// 7. Ignore Forecast & but guard-BG  🛠️
        /// 8. Compute carbsReq → we could move this to MEAL
        /// 9. Decide temp basal → we could do a tempBasalGenerator ?

        // TODO: how to handle output?
        // TODO: how to handle logging?

        return nil
    }

    static func checkDeterminationInputs(
        glucoseStatus: GlucoseStatus?,
        currentTemp _: TempBasal?,
        iobData: [IobResult]?,
        profile: Profile?,
        currentTime: Date = Date()
    ) throws {
        guard let glucoseStatus = glucoseStatus else {
            throw DeterminationError.missingGlucoseStatus
        }
        guard let profile = profile else {
            throw DeterminationError.missingProfile
        }
        let glucoseAge = currentTime.timeIntervalSince(glucoseStatus.date)
        if glucoseAge > 15 * 60 {
            throw DeterminationError.staleGlucoseData(ageMinutes: glucoseAge / 60)
        }
        if glucoseStatus.glucose < 39 || glucoseStatus.glucose > 600 {
            throw DeterminationError.glucoseOutOfRange(glucose: glucoseStatus.glucose)
        }
        if glucoseStatus.noise > 1 {
            throw DeterminationError.cgmNoiseTooHigh(noise: glucoseStatus.noise)
        }
        if glucoseStatus.delta == 0 {
            throw DeterminationError.noDelta
        }
        guard let _ = iobData else {
            throw DeterminationError.missingIob
        }
    }

    static func handleTempBasalCases(
        glucoseStatus: GlucoseStatus,
        profile: Profile,
        currentTemp: TempBasal?,
        currentTime: Date
    ) -> Determination? {
        let glucose = glucoseStatus.glucose
        let noise = glucoseStatus.noise
        let bgTime = glucoseStatus.date
        let minAgo = Decimal(currentTime.timeIntervalSince(bgTime) / 60) // minutes
        let shortAvgDelta = glucoseStatus.shortAvgDelta
        let longAvgDelta = glucoseStatus.longAvgDelta
        let delta = glucoseStatus.delta
        let device = glucoseStatus.device

        // Always use profile-supplied basal
        let basal = profile.currentBasal ?? profile.basalFor(time: currentTime)

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
        // minAgo (BG age) > 12 or < -5 = old/future BG
        if minAgo > 12 || minAgo < -5 {
            reason =
                "If current system time \(currentTime) is correct, then BG data is too old. The last BG data was read \(minAgo) min ago at \(bgTime)"
        }
        // CGM data unchanged (flat)
        if shortAvgDelta == 0 && longAvgDelta == 0 {
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
            minAgo < -5 ||
            (shortAvgDelta == 0 && longAvgDelta == 0)

        // === IF ERROR, CANCEL/SHORTEN TEMPS ===
        guard errorDetected, let currentTemp = currentTemp else { return nil }

        if currentTemp.rate >= basal {
            // Cancel high temp: set 0U/hr for 0m (neutralizes)
            let reasonWithAction = reason + ". Canceling high temp basal of \(currentTemp.rate)U/hr."
            return Determination(
                id: UUID(),
                reason: reasonWithAction,
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
                bg: glucose,
                reservoir: nil,
                isf: profile.sens,
                timestamp: currentTime,
                tdd: nil,
                current_target: profile.targetBg,
                insulinForManualBolus: nil,
                manualBolusErrorString: nil,
                minDelta: minDelta,
                expectedDelta: nil,
                minGuardBG: nil,
                minPredBG: nil,
                threshold: nil,
                carbRatio: profile.carbRatio,
                received: false
            )
        } else if currentTemp.rate == 0, currentTemp.duration > 30 {
            // Shorten long zero temp to 30m
            let reasonWithAction = reason + ". Shortening \(currentTemp.duration)m long zero temp to 30m."
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
                bg: glucose,
                reservoir: nil,
                isf: profile.sens,
                timestamp: currentTime,
                tdd: nil,
                current_target: profile.targetBg,
                insulinForManualBolus: nil,
                manualBolusErrorString: nil,
                minDelta: minDelta,
                expectedDelta: nil,
                minGuardBG: nil,
                minPredBG: nil,
                threshold: nil,
                carbRatio: profile.carbRatio,
                received: false
            )
        } else {
            // Do nothing (temp already safe)
            let reasonWithAction = reason + ". Temp \(currentTemp.rate) <= current basal \(basal)U/hr; doing nothing."
            return Determination(
                id: UUID(),
                reason: reasonWithAction,
                units: nil,
                insulinReq: nil,
                eventualBG: nil,
                sensitivityRatio: nil,
                rate: currentTemp.rate,
                duration: Decimal(currentTemp.duration),
                iob: nil,
                cob: nil,
                predictions: nil,
                deliverAt: currentTime,
                carbsReq: nil,
                temp: currentTemp.temp,
                bg: glucose,
                reservoir: nil,
                isf: profile.sens,
                timestamp: currentTime,
                tdd: nil,
                current_target: profile.targetBg,
                insulinForManualBolus: nil,
                manualBolusErrorString: nil,
                minDelta: minDelta,
                expectedDelta: nil,
                minGuardBG: nil,
                minPredBG: nil,
                threshold: nil,
                carbRatio: profile.carbRatio,
                received: false
            )
        }
    }

    static func calculateSensitivityRatio(
        profile: Profile,
        autosens: Autosens?,
        targetGlucose: Decimal,
        temptargetSet: Bool
    ) -> Decimal {
        let normalTarget: Decimal = 100
        let halfBasalTarget = profile.halfBasalExerciseTarget
        let highTemptargetRaisesSensitivity = profile.highTemptargetRaisesSensitivity
        let lowTemptargetLowersSensitivity = profile.lowTemptargetLowersSensitivity

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
