import Combine
import Foundation
import Swinject

extension TherapyProfileList {
    final class StateModel: BaseStateModel<Provider>, ProfileManagerObserver {
        @Injected() private var profileManager: ProfileManager!
        @Injected() private var broadcaster: Broadcaster!

        @Published var profiles: [TherapyProfile] = []
        @Published var activeProfile: TherapyProfile?
        @Published var isManualOverrideActive: Bool = false
        @Published var showDeleteAlert: Bool = false
        @Published var profileToDelete: TherapyProfile?
        @Published var deleteError: String?

        override func subscribe() {
            profiles = provider.profiles
            activeProfile = provider.activeProfile
            isManualOverrideActive = provider.isManualOverrideActive

            broadcaster.register(ProfileManagerObserver.self, observer: self)
        }

        // MARK: - ProfileManagerObserver

        func activeProfileDidChange(_ profile: TherapyProfile) {
            activeProfile = profile
            isManualOverrideActive = profileManager.isManualOverrideActive
        }

        func profilesDidChange(_ profiles: [TherapyProfile]) {
            self.profiles = profiles
        }

        // MARK: - Actions

        func activateProfile(_ profile: TherapyProfile) {
            profileManager.activateProfile(id: profile.id, reason: .manual)
        }

        func activateProfileAsOverride(_ profile: TherapyProfile) {
            profileManager.activateProfileAsOverride(id: profile.id)
        }

        func clearOverride() {
            profileManager.clearManualOverride()
        }

        func createNewProfile() {
            // Navigate to editor with new profile
            let newProfile = profileManager.createProfile(
                name: generateUniqueName(),
                copyFrom: nil
            )
            showModal(for: .therapyProfileEditor(profile: newProfile, isNew: true))
        }

        func duplicateProfile(_ profile: TherapyProfile) {
            let newProfile = profileManager.createProfile(
                name: "\(profile.name) Copy",
                copyFrom: profile
            )
            showModal(for: .therapyProfileEditor(profile: newProfile, isNew: true))
        }

        func editProfile(_ profile: TherapyProfile) {
            showModal(for: .therapyProfileEditor(profile: profile, isNew: false))
        }

        func confirmDelete(_ profile: TherapyProfile) {
            profileToDelete = profile
            deleteError = nil
            showDeleteAlert = true
        }

        func deleteProfile() {
            guard let profile = profileToDelete else { return }

            do {
                try profileManager.deleteProfile(id: profile.id)
                profileToDelete = nil
                showDeleteAlert = false
            } catch let error as ProfileManagerError {
                deleteError = error.errorDescription
            } catch {
                deleteError = error.localizedDescription
            }
        }

        func canDeleteProfile(_ profile: TherapyProfile) -> Bool {
            !profile.isDefault && activeProfile?.id != profile.id
        }

        // MARK: - Helpers

        private func generateUniqueName() -> String {
            let baseName = NSLocalizedString("New Profile", comment: "Default name for new profile")
            var name = baseName
            var counter = 1

            while profiles.contains(where: { $0.name == name }) {
                counter += 1
                name = "\(baseName) \(counter)"
            }

            return name
        }

        var canCreateProfile: Bool {
            profiles.count < TherapyProfile.maxProfiles
        }

        func daysDescription(for profile: TherapyProfile) -> String {
            profile.activeDays.formattedString
        }
    }
}
