import Foundation

struct OpenAPSSwift {
    static func makeProfile(
        preferences: JSON,
        pumpSettings: JSON,
        bgTargets: JSON,
        basalProfile: JSON,
        isf: JSON,
        carbRatio: JSON,
        tempTargets: JSON,
        model: JSON,
        trioSettings: JSON
    ) -> OrefFunctionResult {
        do {
            let preferences = try JSONBridge.preferences(from: preferences)
            let pumpSettings = try JSONBridge.pumpSettings(from: pumpSettings)
            let bgTargets = try JSONBridge.bgTargets(from: bgTargets)
            let basalProfile = try JSONBridge.basalProfile(from: basalProfile)
            let isf = try JSONBridge.insulinSensitivities(from: isf)
            let carbRatio = try JSONBridge.carbRatios(from: carbRatio)
            let tempTargets = try JSONBridge.tempTargets(from: tempTargets)
            let model = JSONBridge.model(from: model)
            let trioSettings = try JSONBridge.trioSettings(from: trioSettings)

            let profile = try ProfileGenerator.generate(
                pumpSettings: pumpSettings,
                bgTargets: bgTargets,
                basalProfile: basalProfile,
                isf: isf,
                preferences: preferences,
                carbRatios: carbRatio,
                tempTargets: tempTargets,
                model: model,
                trioSettings: trioSettings
            )

            return try .success(JSONBridge.to(profile))
        } catch {
            return .failure(error)
        }
    }

    static func determineBasal(
        glucose: JSON,
        currentTemp: JSON,
        iob: JSON,
        profile: JSON,
        autosens: JSON,
        meal: JSON,
        microBolusAllowed: Bool,
        reservoir: JSON,
        pumpHistory: JSON,
        preferences: JSON,
        basalProfile: JSON,
        trioCustomOrefVariables: JSON,
        clock: Date
    ) -> (OrefFunctionResult, DetermineBasalInputs?) {
        var determineBasalInputs: DetermineBasalInputs?

        print(reservoir)

        do {
            let glucose = try JSONBridge.glucose(from: glucose)
            let currentTemp = try JSONBridge.currentTemp(from: currentTemp)
            let iob = try JSONBridge.iobResult(from: iob)
            let profile = try JSONBridge.profile(from: profile)
            let autosens = try JSONBridge.autosens(from: autosens)
            let meal = try JSONBridge.computedCarbs(from: meal)
            let microBolusAllowed = microBolusAllowed
            let reservoir = Decimal(string: reservoir.rawJSON)
            let pumpHistory = try JSONBridge.pumpHistory(from: pumpHistory)
            let preferences = try JSONBridge.preferences(from: preferences)
            let basalProfile = try JSONBridge.basalProfile(from: basalProfile)
            let trioCustomOrefVariables = try JSONBridge.trioCustomOrefVariables(from: trioCustomOrefVariables)

            determineBasalInputs = DetermineBasalInputs(
                glucose: glucose,
                currentTemp: currentTemp,
                iob: iob,
                profile: profile,
                autosens: autosens,
                meal: meal,
                microBolusAllowed: microBolusAllowed,
                reservoir: reservoir,
                pumpHistory: pumpHistory,
                preferences: preferences,
                basalProfile: basalProfile,
                trioCustomOrefVariables: trioCustomOrefVariables,
                clock: clock
            )

            guard let mealData = meal, let autosensData = autosens else {
                return (.failure(DeterminationError.missingInputs), determineBasalInputs)
            }

            let rawDetermination = try DeterminationGenerator.generate(
                profile: profile,
                preferences: preferences,
                currentTemp: currentTemp,
                iobData: iob,
                mealData: mealData,
                autosensData: autosensData,
                reservoirData: reservoir ?? 100,
                glucose: glucose,
                microBolusAllowed: microBolusAllowed,
                trioCustomOrefVariables: trioCustomOrefVariables,
                currentTime: clock
            )

            return (try .success(JSONBridge.to(rawDetermination)), determineBasalInputs)

        } catch let determinationError as DeterminationError {
            // if we get a determination error we want to return it as a JSON
            // object that is { "error": "some error" }
            do {
                let response = try JSONBridge.to(DeterminationErrorResponse(error: determinationError.localizedDescription))
                return (.success(response), determineBasalInputs)
            } catch {
                return (.failure(determinationError), determineBasalInputs)
            }
        } catch {
            return (.failure(error), determineBasalInputs)
        }
    }

    static func meal(
        pumphistory: JSON,
        profile: JSON,
        basalProfile: JSON,
        clock: JSON,
        carbs: JSON,
        glucose: JSON
    ) -> (OrefFunctionResult, MealInputs?) {
        var mealInputs: MealInputs?

        do {
            let pumpHistory = try JSONBridge.pumpHistory(from: pumphistory)
            let profile = try JSONBridge.profile(from: profile)
            let basalProfile = try JSONBridge.basalProfile(from: basalProfile)
            let clock = try JSONBridge.clock(from: clock)
            let carbs = try JSONBridge.carbs(from: carbs)
            let glucose = try JSONBridge.glucose(from: glucose)

            mealInputs = MealInputs(
                pumpHistory: pumpHistory,
                profile: profile,
                basalProfile: basalProfile,
                clock: clock,
                carbs: carbs,
                glucose: glucose
            )

            let mealResult = try MealGenerator.generate(
                pumpHistory: pumpHistory,
                profile: profile,
                basalProfile: basalProfile,
                clock: clock,
                carbHistory: carbs,
                glucoseHistory: glucose
            )

            return try (.success(JSONBridge.to(mealResult)), mealInputs)
        } catch {
            return (.failure(error), mealInputs)
        }
    }

    static func iob(pumphistory: JSON, profile: JSON, clock: JSON, autosens: JSON) -> (OrefFunctionResult, IobInputs?) {
        var iobInputs: IobInputs?

        do {
            let pumpHistory = try JSONBridge.pumpHistory(from: pumphistory)
            let profile = try JSONBridge.profile(from: profile)
            let clock = try JSONBridge.clock(from: clock)
            let autosens = try JSONBridge.autosens(from: autosens)

            iobInputs = IobInputs(history: pumpHistory, profile: profile, clock: clock, autosens: autosens)

            let iobResult = try IobGenerator.generate(
                history: pumpHistory,
                profile: profile,
                clock: clock,
                autosens: autosens
            )

            return try (.success(JSONBridge.to(iobResult)), iobInputs)
        } catch {
            return (.failure(error), iobInputs)
        }
    }

    static func autosense(
        glucose: JSON,
        pumpHistory: JSON,
        basalProfile: JSON,
        profile: JSON,
        carbs: JSON,
        tempTargets: JSON,
        clock: JSON,
        includeDeviationsForTesting: Bool = false
    ) -> (OrefFunctionResult, AutosensInputs?) {
        var autosensInputs: AutosensInputs?

        do {
            let glucose = try JSONBridge.glucose(from: glucose)
            let pumpHistory = try JSONBridge.pumpHistory(from: pumpHistory)
            let basalProfile = try JSONBridge.basalProfile(from: basalProfile)
            let profile = try JSONBridge.profile(from: profile)
            let carbs = try JSONBridge.carbs(from: carbs)
            let tempTargets = try JSONBridge.tempTargets(from: tempTargets)
            let clock = try JSONBridge.clock(from: clock)

            autosensInputs = AutosensInputs(
                glucose: glucose,
                history: pumpHistory,
                basalProfile: basalProfile,
                profile: profile,
                carbs: carbs,
                tempTargets: tempTargets,
                clock: clock
            )

            // this logic is from prepare/autosens.js
            let ratio8h = try AutosensGenerator.generate(
                glucose: glucose,
                pumpHistory: pumpHistory,
                basalProfile: basalProfile,
                profile: profile,
                carbs: carbs,
                tempTargets: tempTargets,
                maxDeviations: 96,
                clock: clock,
                includeDeviationsForTesting: includeDeviationsForTesting
            )

            let ratio24h = try AutosensGenerator.generate(
                glucose: glucose,
                pumpHistory: pumpHistory,
                basalProfile: basalProfile,
                profile: profile,
                carbs: carbs,
                tempTargets: tempTargets,
                maxDeviations: 288,
                clock: clock,
                includeDeviationsForTesting: includeDeviationsForTesting
            )

            let lowestRatio = ratio8h.ratio < ratio24h.ratio ? ratio8h : ratio24h

            return try (.success(JSONBridge.to(lowestRatio)), autosensInputs)
        } catch {
            return (.failure(error), autosensInputs)
        }
    }
}
