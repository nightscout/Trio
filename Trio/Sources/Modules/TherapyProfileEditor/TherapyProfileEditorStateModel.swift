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

        // MARK: - Therapy Settings

        @Published var basalProfile: [BasalProfileEntry] = []
        @Published var insulinSensitivities: InsulinSensitivities?
        @Published var carbRatios: CarbRatios?
        @Published var bgTargets: BGTargets?

        // MARK: - UI State

        @Published var showCopySheet: Bool = false
        @Published var expandedSection: SettingsSection?

        enum SettingsSection: String, CaseIterable {
            case basal
            case isf
            case carbRatio
            case targets
        }

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

            Publishers.CombineLatest3($insulinSensitivities, $carbRatios, $bgTargets)
                .dropFirst()
                .sink { [weak self] _ in
                    self?.hasChanges = true
                }
                .store(in: &cancellables)
        }

        // MARK: - Computed Properties

        var conflictingDays: Set<Weekday> {
            guard let provider = provider else { return [] }
            var conflicts = Set<Weekday>()
            for profile in provider.allProfiles where profile.id != profileId {
                conflicts.formUnion(profile.activeDays)
            }
            return conflicts
        }

        var conflictingDayOwners: [Weekday: String] {
            guard let provider = provider else { return [:] }
            var owners: [Weekday: String] = [:]
            for profile in provider.allProfiles where profile.id != profileId {
                for day in profile.activeDays {
                    owners[day] = profile.name
                }
            }
            return owners
        }

        var canSave: Bool {
            !name.isEmpty && nameError == nil
        }

        var units: GlucoseUnits {
            provider?.units ?? .mgdL
        }

        var availableProfilesForCopy: [TherapyProfile] {
            guard let provider = provider else { return [] }
            return provider.allProfiles.filter { $0.id != profileId }
        }

        var hasCurrentActiveSettings: Bool {
            provider?.hasCurrentActiveSettings ?? false
        }

        // MARK: - Actions

        func validateName() {
            let trimmedName = name.trimmingCharacters(in: .whitespaces)

            if trimmedName.isEmpty {
                nameError = NSLocalizedString("Profile name is required", comment: "Validation error")
                return
            }

            guard let provider = provider else {
                nameError = nil
                return
            }

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

        // MARK: - Copy Settings

        func showCopyOptions() {
            showCopySheet = true
        }

        func copySettingsFrom(profile: TherapyProfile) {
            basalProfile = profile.basalProfile
            insulinSensitivities = profile.insulinSensitivities
            carbRatios = profile.carbRatios
            bgTargets = profile.bgTargets
            hasChanges = true
        }

        func copyFromCurrentActiveSettings() {
            guard let provider = provider else { return }
            let currentBasal = provider.currentBasalProfile
            let currentISF = provider.currentInsulinSensitivities
            let currentCR = provider.currentCarbRatios
            let currentTargets = provider.currentBGTargets

            basalProfile = currentBasal
            if let isf = currentISF {
                insulinSensitivities = isf
            }
            if let cr = currentCR {
                carbRatios = cr
            }
            if let targets = currentTargets {
                bgTargets = targets
            }
            hasChanges = true
        }

        // MARK: - Section Expansion

        func toggleSection(_ section: SettingsSection) {
            if expandedSection == section {
                expandedSection = nil
            } else {
                expandedSection = section
            }
        }

        // MARK: - Basal Rate Editing

        func addBasalEntry() {
            let newEntry = BasalProfileEntry(
                start: nextAvailableBasalTime(),
                minutes: nextAvailableBasalMinutes(),
                rate: 0.0
            )
            basalProfile.append(newEntry)
            basalProfile.sort { $0.minutes < $1.minutes }
        }

        func updateBasalEntry(at index: Int, rate: Decimal) {
            guard index < basalProfile.count else { return }
            let existing = basalProfile[index]
            basalProfile[index] = BasalProfileEntry(start: existing.start, minutes: existing.minutes, rate: rate)
        }

        func updateBasalEntryTime(at index: Int, minutes: Int) {
            guard index < basalProfile.count else { return }
            let existing = basalProfile[index]
            basalProfile[index] = BasalProfileEntry(start: minutesToTimeString(minutes), minutes: minutes, rate: existing.rate)
            basalProfile.sort { $0.minutes < $1.minutes }
        }

        func deleteBasalEntry(at index: Int) {
            guard index < basalProfile.count else { return }
            basalProfile.remove(at: index)
        }

        private func nextAvailableBasalTime() -> String {
            if basalProfile.isEmpty {
                return "00:00"
            }
            let lastMinutes = basalProfile.last?.minutes ?? 0
            let nextMinutes = min(lastMinutes + 60, 23 * 60)
            return minutesToTimeString(nextMinutes)
        }

        private func nextAvailableBasalMinutes() -> Int {
            if basalProfile.isEmpty {
                return 0
            }
            let lastMinutes = basalProfile.last?.minutes ?? 0
            return min(lastMinutes + 60, 23 * 60)
        }

        private func minutesToTimeString(_ minutes: Int) -> String {
            let hours = minutes / 60
            let mins = minutes % 60
            return String(format: "%02d:%02d", hours, mins)
        }

        // MARK: - ISF Editing

        func addISFEntry() {
            guard var isf = insulinSensitivities else {
                insulinSensitivities = InsulinSensitivities(
                    units: units,
                    userPreferredUnits: units,
                    sensitivities: [InsulinSensitivityEntry(sensitivity: 0, offset: 0, start: "00:00")]
                )
                return
            }
            let nextOffset = (isf.sensitivities.last?.offset ?? 0) + 60
            let newEntry = InsulinSensitivityEntry(
                sensitivity: isf.sensitivities.last?.sensitivity ?? 0,
                offset: min(nextOffset, 23 * 60),
                start: minutesToTimeString(min(nextOffset, 23 * 60))
            )
            isf.sensitivities.append(newEntry)
            isf.sensitivities.sort { $0.offset < $1.offset }
            insulinSensitivities = isf
        }

        func updateISFEntry(at index: Int, sensitivity: Decimal) {
            guard var isf = insulinSensitivities, index < isf.sensitivities.count else { return }
            let existing = isf.sensitivities[index]
            isf.sensitivities[index] = InsulinSensitivityEntry(sensitivity: sensitivity, offset: existing.offset, start: existing.start)
            insulinSensitivities = isf
        }

        func deleteISFEntry(at index: Int) {
            guard var isf = insulinSensitivities, index < isf.sensitivities.count else { return }
            isf.sensitivities.remove(at: index)
            insulinSensitivities = isf
        }

        // MARK: - Carb Ratio Editing

        func addCarbRatioEntry() {
            guard let cr = carbRatios else {
                carbRatios = CarbRatios(
                    units: .grams,
                    schedule: [CarbRatioEntry(start: "00:00", offset: 0, ratio: 0)]
                )
                return
            }
            let nextOffset = (cr.schedule.last?.offset ?? 0) + 60
            let newEntry = CarbRatioEntry(
                start: minutesToTimeString(min(nextOffset, 23 * 60)),
                offset: min(nextOffset, 23 * 60),
                ratio: cr.schedule.last?.ratio ?? 0
            )
            var newSchedule = cr.schedule
            newSchedule.append(newEntry)
            newSchedule.sort { $0.offset < $1.offset }
            carbRatios = CarbRatios(units: cr.units, schedule: newSchedule)
        }

        func updateCarbRatioEntry(at index: Int, ratio: Decimal) {
            guard let cr = carbRatios, index < cr.schedule.count else { return }
            let existing = cr.schedule[index]
            var newSchedule = cr.schedule
            newSchedule[index] = CarbRatioEntry(start: existing.start, offset: existing.offset, ratio: ratio)
            carbRatios = CarbRatios(units: cr.units, schedule: newSchedule)
        }

        func deleteCarbRatioEntry(at index: Int) {
            guard let cr = carbRatios, index < cr.schedule.count else { return }
            var newSchedule = cr.schedule
            newSchedule.remove(at: index)
            carbRatios = CarbRatios(units: cr.units, schedule: newSchedule)
        }

        // MARK: - Glucose Targets Editing

        func addTargetEntry() {
            guard var targets = bgTargets else {
                bgTargets = BGTargets(
                    units: units,
                    userPreferredUnits: units,
                    targets: [BGTargetEntry(low: 100, high: 120, start: "00:00", offset: 0)]
                )
                return
            }
            let nextOffset = (targets.targets.last?.offset ?? 0) + 60
            let newEntry = BGTargetEntry(
                low: targets.targets.last?.low ?? 100,
                high: targets.targets.last?.high ?? 120,
                start: minutesToTimeString(min(nextOffset, 23 * 60)),
                offset: min(nextOffset, 23 * 60)
            )
            targets.targets.append(newEntry)
            targets.targets.sort { $0.offset < $1.offset }
            bgTargets = targets
        }

        func updateTargetEntry(at index: Int, low: Decimal, high: Decimal) {
            guard var targets = bgTargets, index < targets.targets.count else { return }
            let existing = targets.targets[index]
            targets.targets[index] = BGTargetEntry(low: low, high: high, start: existing.start, offset: existing.offset)
            bgTargets = targets
        }

        func deleteTargetEntry(at index: Int) {
            guard var targets = bgTargets, index < targets.targets.count else { return }
            targets.targets.remove(at: index)
            bgTargets = targets
        }
    }
}
