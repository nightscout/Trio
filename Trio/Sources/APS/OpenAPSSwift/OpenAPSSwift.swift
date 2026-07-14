import Foundation

struct OpenAPSSwift {
    static func makeProfile(
        preferences: Preferences,
        pumpSettings: PumpSettings,
        bgTargets: BGTargets,
        basalProfile: [BasalProfileEntry],
        insulinSensitivities: InsulinSensitivities,
        carbRatios: CarbRatios,
        tempTargets: [TempTarget],
        model: String,
        clock: Date
    ) throws -> Profile {
        try ProfileGenerator.generate(
            pumpSettings: pumpSettings,
            bgTargets: bgTargets,
            basalProfile: basalProfile,
            isf: insulinSensitivities,
            preferences: preferences,
            carbRatios: carbRatios,
            tempTargets: tempTargets,
            model: model,
            clock: clock
        )
    }

    static func determineBasal(
        glucose: [BloodGlucose],
        currentTemp: JSON,
        iob: JSON,
        profile: JSON,
        autosens: JSON,
        meal: JSON,
        microBolusAllowed: Bool,
        reservoir: JSON,
        preferences: JSON,
        basalProfile: JSON,
        trioCustomOrefVariables: JSON,
        clock: Date
    ) -> (OrefFunctionResult) {
        do {
            let currentTemp = try JSONBridge.currentTemp(from: currentTemp)
            let iob = try JSONBridge.iobResult(from: iob)
            let profile = try JSONBridge.profile(from: profile)
            let autosens = try JSONBridge.autosens(from: autosens)
            let meal = try JSONBridge.computedCarbs(from: meal)
            let microBolusAllowed = microBolusAllowed
            let reservoir = Decimal(string: reservoir.rawJSON)
            let preferences = try JSONBridge.preferences(from: preferences)
            let basalProfile = try JSONBridge.basalProfile(from: basalProfile)
            let trioCustomOrefVariables = try JSONBridge.trioCustomOrefVariables(from: trioCustomOrefVariables)

            guard let mealData = meal, let autosensData = autosens else {
                return .failure(DeterminationError.missingInputs)
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

            return try .success(JSONBridge.to(rawDetermination))

        } catch let determinationError as DeterminationError {
            // if we get a determination error we want to return it as a JSON
            // object that is { "error": "some error" }
            do {
                let response = try JSONBridge.to(DeterminationErrorResponse(error: determinationError.localizedDescription))
                return .success(response)
            } catch {
                return .failure(determinationError)
            }
        } catch {
            return .failure(error)
        }
    }

    static func meal(
        pumphistory: [PumpHistoryEvent],
        profile: JSON,
        basalProfile: JSON,
        clock: JSON,
        carbs: [CarbsEntry],
        glucose: [BloodGlucose]
    ) -> (OrefFunctionResult) {
        do {
            let profile = try JSONBridge.profile(from: profile)
            let basalProfile = try JSONBridge.basalProfile(from: basalProfile)
            let clock = try JSONBridge.clock(from: clock)

            let mealResult = try MealGenerator.generate(
                pumpHistory: pumphistory,
                profile: profile,
                basalProfile: basalProfile,
                clock: clock,
                carbHistory: carbs,
                glucoseHistory: glucose
            )

            return try .success(JSONBridge.to(mealResult))
        } catch {
            return .failure(error)
        }
    }

    static func iob(pumphistory: [PumpHistoryEvent], profile: JSON, clock: JSON, autosens: JSON) -> (OrefFunctionResult) {
        do {
            let profile = try JSONBridge.profile(from: profile)
            let clock = try JSONBridge.clock(from: clock)
            let autosens = try JSONBridge.autosens(from: autosens)

            let iobResult = try IobGenerator.generate(
                history: pumphistory,
                profile: profile,
                clock: clock,
                autosens: autosens
            )

            return try .success(JSONBridge.to(iobResult))
        } catch {
            return .failure(error)
        }
    }

    static func autosense(
        glucose: [BloodGlucose],
        pumpHistory: [PumpHistoryEvent],
        basalProfile: JSON,
        profile: JSON,
        carbs: [CarbsEntry],
        tempTargets: JSON,
        clock: JSON,
        includeDeviationsForTesting: Bool = false
    ) -> (OrefFunctionResult) {
        do {
            let basalProfile = try JSONBridge.basalProfile(from: basalProfile)
            let profile = try JSONBridge.profile(from: profile)
            let tempTargets = try JSONBridge.tempTargets(from: tempTargets)
            let clock = try JSONBridge.clock(from: clock)

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

            return try .success(JSONBridge.to(lowestRatio))
        } catch {
            return .failure(error)
        }
    }
}
