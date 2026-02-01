import Foundation

extension ISFTiersEditor {
    final class Provider: BaseProvider, ISFTiersEditorProvider {
        var tiersSettings: InsulinSensitivityTiers {
            storage.retrieve(OpenAPS.Settings.insulinSensitivityTiers, as: InsulinSensitivityTiers.self)
                ?? InsulinSensitivityTiers(enabled: false, tiers: InsulinSensitivityTier.defaultTiers)
        }

        func saveTiersSettings(_ settings: InsulinSensitivityTiers) {
            storage.save(settings, as: OpenAPS.Settings.insulinSensitivityTiers)
        }
    }
}
