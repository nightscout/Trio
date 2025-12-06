import Combine

extension Onboarding {
    final class Provider: BaseProvider, MainProvider {
        var glucoseTargetsOnFile: BGTargets {
            var retrievedTargets = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
                ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])

            // migrate existing mmol/L Trio users from mmol/L settings to pure mg/dl settings
            if retrievedTargets.units == .mmolL || retrievedTargets.userPreferredUnits == .mmolL {
                let convertedTargets = retrievedTargets.targets.map { target in
                    BGTargetEntry(
                        low: storage.parseSettingIfMmolL(value: target.low),
                        high: storage.parseSettingIfMmolL(value: target.high),
                        start: target.start,
                        offset: target.offset
                    )
                }
                retrievedTargets = BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: convertedTargets)
            }

            return retrievedTargets
        }

        var basalProfileOnFile: [BasalProfileEntry] {
            storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
                ?? []
        }

        var carbRatiosOnFile: CarbRatios {
            storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self) ?? CarbRatios(units: .grams, schedule: [])
        }

        var isfOnFile: InsulinSensitivities {
            var retrievedSensitivities = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
                ?? InsulinSensitivities(from: OpenAPS.defaults(for: OpenAPS.Settings.insulinSensitivities))
                ?? InsulinSensitivities(
                    units: .mgdL,
                    userPreferredUnits: .mgdL,
                    sensitivities: []
                )

            // migrate existing mmol/L Trio users from mmol/L settings to pure mg/dl settings
            if retrievedSensitivities.units == .mmolL || retrievedSensitivities.userPreferredUnits == .mmolL {
                let convertedSensitivities = retrievedSensitivities.sensitivities.map { isf in
                    InsulinSensitivityEntry(
                        sensitivity: storage.parseSettingIfMmolL(value: isf.sensitivity),
                        offset: isf.offset,
                        start: isf.start
                    )
                }
                retrievedSensitivities = InsulinSensitivities(
                    units: .mgdL,
                    userPreferredUnits: .mgdL,
                    sensitivities: convertedSensitivities
                )
            }

            return retrievedSensitivities
        }

        var pumpSettingsFromFile: PumpSettings? {
            storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
                ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
        }
    }
}
