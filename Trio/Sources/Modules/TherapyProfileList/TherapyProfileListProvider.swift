import Foundation
import Swinject

extension TherapyProfileList {
    final class Provider: BaseProvider, TherapyProfileListProvider {
        @Injected() private var profileManager: ProfileManager!

        var profiles: [TherapyProfile] {
            profileManager.profiles
        }

        var activeProfile: TherapyProfile? {
            profileManager.activeProfile
        }

        var isManualOverrideActive: Bool {
            profileManager.isManualOverrideActive
        }
    }
}
