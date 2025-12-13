import Combine
import Foundation
import Swinject

extension TherapyProfileEditor {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var profileManager: ProfileManager!

        // MARK: - Published Properties

        @Published var name: String = ""
        @Published var activeDays: Set<Weekday> = []
        @Published var isDefault: Bool = false
        @Published var hasChanges: Bool = false
        @Published var showDiscardAlert: Bool = false
        @Published var nameError: String?

        // MARK: - Therapy Settings (read from profile)

        @Published var basalProfile: [BasalProfileEntry] = []
        @Published var insulinSensitivities: InsulinSensitivities?
        @Published var carbRatios: CarbRatios?
        @Published var bgTargets: BGTargets?

        // MARK: - Private Properties

        private var originalProfile: TherapyProfile?
        private var isNew: Bool = false
        private var cancellables = Set<AnyCancellable>()

        var profileId: UUID {
            originalProfile?.id ?? UUID()
        }

        override func subscribe() {
            guard let profile = provider.profile else {
                return
            }

            originalProfile = profile
            isNew = provider.isNew

            // Load values from profile
            name = profile.name
            activeDays = profile.activeDays
            isDefault = profile.isDefault
            basalProfile = profile.basalProfile
            insulinSensitivities = profile.insulinSensitivities
            carbRatios = profile.carbRatios
            bgTargets = profile.bgTargets

            // Track changes
            setupChangeTracking()
        }

        private func setupChangeTracking() {
            Publishers.CombineLatest4($name, $activeDays, $isDefault, $basalProfile)
                .dropFirst()
                .sink { [weak self] _ in
                    self?.hasChanges = true
                }
                .store(in: &cancellables)
        }

        // MARK: - Computed Properties

        var conflictingDays: Set<Weekday> {
            // Find days assigned to other profiles
            var conflicts = Set<Weekday>()
            for profile in provider.allProfiles where profile.id != profileId {
                conflicts.formUnion(profile.activeDays)
            }
            return conflicts
        }

        var canSave: Bool {
            !name.isEmpty && nameError == nil
        }

        var units: GlucoseUnits {
            provider.units
        }

        // MARK: - Actions

        func validateName() {
            let trimmedName = name.trimmingCharacters(in: .whitespaces)

            if trimmedName.isEmpty {
                nameError = NSLocalizedString("Profile name is required", comment: "Validation error")
                return
            }

            // Check for duplicate names (excluding current profile)
            let isDuplicate = provider.allProfiles.contains { profile in
                profile.id != profileId && profile.name.lowercased() == trimmedName.lowercased()
            }

            if isDuplicate {
                nameError = NSLocalizedString("A profile with this name already exists", comment: "Validation error")
                return
            }

            nameError = nil
        }

        func save() {
            validateName()
            guard canSave else { return }

            guard var profile = originalProfile else { return }

            profile.name = name.trimmingCharacters(in: .whitespaces)
            profile.activeDays = activeDays
            profile.isDefault = isDefault
            profile.basalProfile = basalProfile
            if let isf = insulinSensitivities {
                profile.insulinSensitivities = isf
            }
            if let cr = carbRatios {
                profile.carbRatios = cr
            }
            if let targets = bgTargets {
                profile.bgTargets = targets
            }

            profileManager.updateProfile(profile)
            hasChanges = false
            hideModal()
        }

        func discardChanges() {
            hasChanges = false
            hideModal()
        }

        func confirmDiscard() {
            if hasChanges {
                showDiscardAlert = true
            } else {
                hideModal()
            }
        }

        // MARK: - Navigation to Editors

        func editBasalRates() {
            // Navigate to basal editor with callback
            showModal(for: .basalProfileEditor)
        }

        func editInsulinSensitivities() {
            showModal(for: .isfEditor)
        }

        func editCarbRatios() {
            showModal(for: .crEditor)
        }

        func editGlucoseTargets() {
            showModal(for: .targetsEditor)
        }
    }
}
