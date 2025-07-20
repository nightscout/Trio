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
        preferences: Preferences,
        currentTemp: TempBasal,
        iobData: [IobResult],
        mealData: ComputedCarbs,
        autosensData: Autosens,
        reservoirData _: Decimal,
        glucose: [BloodGlucose],
        trioCustomOrefVariables: TrioCustomOrefVariables,
        currentTime: Date
    ) throws -> Determination? {
        var autosensData = autosensData
        let glucoseStatus = try Self.getGlucoseStatus(glucoseReadings: glucose)

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

        let sensitivityRatio: Decimal
        let dynamicIsfResult = DynamicISF.calculate(
            profile: profile,
            preferences: preferences,
            currentGlucose: currentGlucose,
            trioCustomOrefVariables: trioCustomOrefVariables
        )

        // TODO: We need to add the dynamicIsfResult to our forcasting functions
        if let dynamicIsfResult = dynamicIsfResult {
            sensitivityRatio = dynamicIsfResult.ratio
            autosensData = Autosens(
                ratio: dynamicIsfResult.ratio,
                newisf: autosensData.newisf,
                deviationsUnsorted: autosensData.deviationsUnsorted,
                timestamp: autosensData.timestamp
            )
        } else {
            sensitivityRatio = calculateSensitivityRatio(
                profile: profile,
                autosens: autosensData,
                targetGlucose: profile.profileTarget(trioCustomOrefVariables: trioCustomOrefVariables) ?? 120,
                temptargetSet: profile.temptargetSet ?? false
            )
        }

        let basal: Decimal
        if let dynamicIsfResult = dynamicIsfResult, profile.tddAdjBasal {
            basal = computeAdjustedBasal(
                currentBasalRate: profile.currentBasal ?? profile.basalFor(time: currentTime),
                sensitivityRatio: dynamicIsfResult.tddRatio
            )
        } else {
            basal = computeAdjustedBasal(
                currentBasalRate: profile.currentBasal ?? profile.basalFor(time: currentTime),
                sensitivityRatio: sensitivityRatio
            )
        }
        let sensitivity = computeAdjustedSensitivity(
            sensitivity: profile.sens ?? profile.sensitivityFor(time: currentTime),
            sensitivityRatio: sensitivityRatio
        )

        // Safety check: current temp vs. last temp in iob
        guard let lastTempTarget = iobData.first?.lastTemp else {
            throw DeterminationError.missingIob
        }
        if !checkCurrentTempBasalRateSafety(
            currentTemp: currentTemp,
            lastTempTarget: lastTempTarget,
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
                iob: iobData.first?.iob,
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
        let glucoseImpactSeriesWithZeroTemp = buildGlucoseImpactSeries(
            iobDataSeries: iobData,
            sensitivity: sensitivity,
            withZeroTemp: true
        )

        guard let currentGlucoseImpact = glucoseImpactSeries.first?.jsRounded(scale: 2) else {
            throw DeterminationError.determinationError
        }

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
        guard let currentIob = iobData.first?.iob else {
            throw DeterminationError.missingIob
        }

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

        let forecastResult = ForecastGenerator.generate(
            glucose: currentGlucose,
            glucoseImpactSeries: glucoseImpactSeries,
            glucoseImpactSeriesWithZeroTemp: glucoseImpactSeriesWithZeroTemp,
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

        // used for pre dosing decision sanity later on
        let expectedDelta = calculateExpectedDelta(
            targetGlucose: profile.minBg ?? 100,
            eventualGlucose: eventualGlucose,
            glucoseImpact: currentGlucoseImpact
        )

        // TODO: STOPPING at LINE 1152

        // FIXME: properly populate all fields!
        let temporaryResult = Determination(
            id: UUID(),
            reason: "FOR TESTING: output after forecasting",
            units: nil,
            insulinReq: nil,
            eventualBG: Int(forecastResult.eventualGlucose),
            sensitivityRatio: sensitivityRatio, // this would only the AS-adjusted one for now
            rate: nil,
            duration: nil,
            iob: iobData.first?.iob,
            cob: mealData.mealCOB,
            predictions: Predictions(
                iob: forecastResult.iob.map { Int($0) },
                zt: forecastResult.zt.map { Int($0) },
                cob: forecastResult.cob.map { Int($0) },
                uam: forecastResult.uam.map { Int($0) }
            ),
            deliverAt: currentTime,
            carbsReq: nil,
            temp: nil,
            bg: currentGlucose,
            reservoir: nil,
            isf: nil,
            timestamp: currentTime,
            tdd: nil,
            current_target: nil,
            insulinForManualBolus: nil,
            manualBolusErrorString: nil,
            minDelta: nil,
            expectedDelta: expectedDelta,
            minGuardBG: forecastResult.minGuardGlucose,
            minPredBG: forecastResult.minForecastedGlucose,
            threshold: threshold,
            carbRatio: nil,
            received: false,
        )

        // TODO: how to handle output?
        // TODO: how to handle logging?

        return temporaryResult
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
}
