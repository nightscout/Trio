extension Treatments {
    final class Provider: BaseProvider, TreatmentsProvider {
        func getPumpSettings() async -> PumpSettings {
            await storage.retrieveAsync(OpenAPS.Settings.settings, as: PumpSettings.self)
                ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
                ?? PumpSettings(insulinActionCurve: 10, maxBolus: 10, maxBasal: 2)
        }

        func getBasalProfile() async -> [BasalProfileEntry] {
            therapyProfileStorage.liveSettings.basalProfileEntries
        }

        func getCarbRatios() async -> CarbRatios {
            therapyProfileStorage.liveSettings.carbRatios
        }

        func getBGTargets() async -> BGTargets {
            therapyProfileStorage.liveSettings.bgTargets
        }

        func getISFValues() async -> InsulinSensitivities {
            therapyProfileStorage.liveSettings.insulinSensitivities
        }

        func getPreferences() async -> Preferences {
            await storage.retrieveAsync(OpenAPS.Settings.preferences, as: Preferences.self)
                ?? Preferences(from: OpenAPS.defaults(for: OpenAPS.Settings.preferences))
                ?? Preferences(maxIOB: 0, maxCOB: 120)
        }
    }
}
