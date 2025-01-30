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
        autotune: JSON,
        freeaps: JSON
    ) -> RawJSON {
        do {
            let preferences = try JSONBridge.preferences(from: preferences)
            let pumpSettings = try JSONBridge.pumpSettings(from: pumpSettings)
            let bgTargets = try JSONBridge.bgTargets(from: bgTargets)
            let basalProfile = try JSONBridge.basalProfile(from: basalProfile)
            let isf = try JSONBridge.insulinSensitivities(from: isf)
            let carbRatio = try JSONBridge.carbRatios(from: carbRatio)
            let tempTargets = try JSONBridge.tempTargets(from: tempTargets)
            let model = JSONBridge.model(from: model)
            let autotune = try JSONBridge.autotune(from: autotune)
            let freeaps = try JSONBridge.freeapsSettings(from: freeaps)

            let profile = try ProfileGenerator.generate(
                pumpSettings: pumpSettings,
                bgTargets: bgTargets,
                basalProfile: basalProfile,
                isf: isf,
                preferences: preferences,
                carbRatios: carbRatio,
                tempTargets: tempTargets,
                model: model,
                autotune: autotune,
                freeaps: freeaps
            )

            return try JSONBridge.to(profile)
        } catch {
            warning(.openAPS, "OpenAPSSwift exception \(error)")
            return .null
        }
    }
}
