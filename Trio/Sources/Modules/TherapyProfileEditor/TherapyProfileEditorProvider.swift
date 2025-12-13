import Foundation
import Swinject

extension TherapyProfileEditor {
    final class Provider: BaseProvider, TherapyProfileEditorProvider {
        @Injected() private var profileManager: ProfileManager!
        @Injected() private var settingsManager: SettingsManager!

        var profile: TherapyProfile? {
            Config.profile
        }

        var isNew: Bool {
            Config.isNew
        }

        var allProfiles: [TherapyProfile] {
            profileManager.profiles
        }

        var units: GlucoseUnits {
            settingsManager.settings.units
        }

        // MARK: - Current Active Settings (for copy feature)

        var hasCurrentActiveSettings: Bool {
            !currentBasalProfile.isEmpty
        }

        var currentBasalProfile: [BasalProfileEntry] {
            storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self) ?? []
        }

        var currentInsulinSensitivities: InsulinSensitivities? {
            storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
        }

        var currentCarbRatios: CarbRatios? {
            storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
        }

        var currentBGTargets: BGTargets? {
            storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
        }
    }
}
