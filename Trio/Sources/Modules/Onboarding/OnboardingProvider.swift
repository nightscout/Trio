import Combine

extension Onboarding {
    final class Provider: BaseProvider, MainProvider {
        /// Nil until therapy settings are first stored, on a fresh install.
        private var storedTherapySettings: TrioTherapyProfile? {
            therapyProfileStorage.storedLiveSettings
        }

        var glucoseTargetsOnFile: BGTargets {
            storedTherapySettings?.bgTargets ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])
        }

        var basalProfileOnFile: [BasalProfileEntry] {
            storedTherapySettings?.basalProfileEntries ?? []
        }

        var carbRatiosOnFile: CarbRatios {
            storedTherapySettings?.carbRatios ?? CarbRatios(units: .grams, schedule: [])
        }

        var isfOnFile: InsulinSensitivities {
            storedTherapySettings?.insulinSensitivities ?? TrioTherapyProfile.bundledDefaults.insulinSensitivities
        }

        var pumpSettingsFromFile: PumpSettings? {
            storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
                ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
        }
    }
}
