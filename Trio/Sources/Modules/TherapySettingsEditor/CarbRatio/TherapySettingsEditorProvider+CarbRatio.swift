import Foundation

extension TherapySettingsEditor.Provider {
    var carbRatioProfile: CarbRatios {
        storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
            ?? CarbRatios(from: OpenAPS.defaults(for: OpenAPS.Settings.carbRatios))
            ?? CarbRatios(units: .grams, schedule: [])
    }

    func saveCarbRatioProfile(_ profile: CarbRatios) {
        storage.save(profile, as: OpenAPS.Settings.carbRatios)
    }
}
