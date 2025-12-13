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
    }
}
