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

            /*
             let result = DeterminationGenerator.generate(profile: profile, currentTemp: <#T##TempBasal#>, iobData: iob, mealData: meal, autosensData: autosens, reservoirData: <#T##Reservoir#>, glucoseStatus: <#T##GlucoseStatus?#>, currentTime: clock)
              */

            // FIXME: fill in with result once we have it
            // return (.success(JSONBridge.to(result)), determineBasalInputs)
            return (.success(RawJSON.null), determineBasalInputs)

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
        glucose _: JSON,
        pumpHistory _: JSON,
        basalprofile _: JSON,
        profile _: JSON,
        carbs _: JSON,
        temptargets _: JSON
    ) -> OrefFunctionResult {
        .failure(NSError(domain: "Some error", code: 1, userInfo: nil))
    }
}
