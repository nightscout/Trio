import Combine
import Foundation
import Swinject

final class BaseProfileManager: ProfileManager, Injectable {
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settingsManager: SettingsManager!

    // MARK: - Published Properties

    @Published private(set) var profiles: [TherapyProfile] = []
    @Published private(set) var activeProfile: TherapyProfile?
    @Published var pendingSwitchNotification: ProfileSwitchEvent?
    @Published private(set) var switchHistory: [ProfileSwitchEvent] = []

    // MARK: - Override State

    private(set) var manualOverrideProfileId: UUID?
    private(set) var manualOverrideDate: Date?

    var isManualOverrideActive: Bool {
        guard let overrideDate = manualOverrideDate else { return false }
        // Override is active if it was set today
        return Calendar.current.isDateInToday(overrideDate)
    }

    // MARK: - Publishers

    var activeProfilePublisher: AnyPublisher<TherapyProfile?, Never> {
        $activeProfile.eraseToAnyPublisher()
    }

    var pendingSwitchNotificationPublisher: AnyPublisher<ProfileSwitchEvent?, Never> {
        $pendingSwitchNotification.eraseToAnyPublisher()
    }

    // MARK: - Private Properties

    private var lastSwitchDate: Date?
    private var subscriptions = Set<AnyCancellable>()

    // MARK: - Initialization

    init(resolver: Resolver) {
        injectServices(resolver)
        loadProfiles()
        loadSwitchHistory()
        loadOverrideState()

        // If no profiles exist, migrate from single profile system
        if profiles.isEmpty {
            migrateFromSingleProfile()
        }

        // Load active profile
        loadActiveProfile()
    }

    // MARK: - Profile Management

    func createProfile(name: String, copyFrom: TherapyProfile?) -> TherapyProfile {
        let newProfile: TherapyProfile

        if let source = copyFrom {
            newProfile = source.copy(withName: name)
        } else {
            // Create with default/empty settings
            let units = settingsManager.settings.units
            newProfile = TherapyProfile(
                name: name,
                activeDays: [],
                basalProfile: [],
                insulinSensitivities: InsulinSensitivities(
                    units: units,
                    userPreferredUnits: units,
                    sensitivities: []
                ),
                carbRatios: CarbRatios(units: .grams, schedule: []),
                bgTargets: BGTargets(
                    units: units,
                    userPreferredUnits: units,
                    targets: []
                ),
                isDefault: profiles.isEmpty
            )
        }

        profiles.append(newProfile)
        saveProfiles()
        notifyProfilesChanged()

        return newProfile
    }

    func updateProfile(_ profile: TherapyProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            return
        }

        var updatedProfile = profile
        updatedProfile.touch()

        // Handle day uniqueness - remove these days from other profiles
        for (idx, existingProfile) in profiles.enumerated() where idx != index {
            let conflictingDays = existingProfile.activeDays.intersection(updatedProfile.activeDays)
            if !conflictingDays.isEmpty {
                var modified = existingProfile
                modified.activeDays.subtract(conflictingDays)
                modified.touch()
                profiles[idx] = modified
            }
        }

        // Handle default flag - only one profile can be default
        if updatedProfile.isDefault {
            for (idx, existingProfile) in profiles.enumerated() where existingProfile.id != updatedProfile.id {
                if existingProfile.isDefault {
                    var modified = existingProfile
                    modified.isDefault = false
                    profiles[idx] = modified
                }
            }
        }

        profiles[index] = updatedProfile
        saveProfiles()
        notifyProfilesChanged()

        // If this is the active profile, update it and write settings
        if activeProfile?.id == profile.id {
            activeProfile = updatedProfile
            writeProfileSettingsToFiles(updatedProfile)
            notifyActiveProfileChanged(updatedProfile)
        }
    }

    func deleteProfile(id: UUID) throws {
        guard let profile = profiles.first(where: { $0.id == id }) else {
            throw ProfileManagerError.profileNotFound
        }

        if profile.isDefault {
            throw ProfileManagerError.cannotDeleteDefaultProfile
        }

        if activeProfile?.id == id {
            throw ProfileManagerError.cannotDeleteActiveProfile
        }

        profiles.removeAll { $0.id == id }
        saveProfiles()
        notifyProfilesChanged()
    }

    // MARK: - Activation

    func activateProfile(id: UUID, reason: ProfileSwitchEvent.SwitchReason) {
        guard let profile = profiles.first(where: { $0.id == id }) else {
            return
        }

        let previousProfile = activeProfile
        let switchEvent = ProfileSwitchEvent(
            fromProfileId: previousProfile?.id,
            fromProfileName: previousProfile?.name,
            toProfileId: profile.id,
            toProfileName: profile.name,
            weekday: .today,
            reason: reason
        )

        activeProfile = profile
        saveActiveProfileId(profile.id)
        writeProfileSettingsToFiles(profile)

        // Add to history
        switchHistory.insert(switchEvent, at: 0)
        // Keep only last 100 events
        if switchHistory.count > 100 {
            switchHistory = Array(switchHistory.prefix(100))
        }
        saveSwitchHistory()

        // Set pending notification for banner
        pendingSwitchNotification = switchEvent

        notifyActiveProfileChanged(profile)

        debug(.service, "Profile switched to '\(profile.name)' - reason: \(reason.rawValue)")
    }

    func activateProfileAsOverride(id: UUID) {
        manualOverrideProfileId = id
        manualOverrideDate = Date()
        saveOverrideState()

        activateProfile(id: id, reason: .manualOverride)
    }

    func clearManualOverride() {
        manualOverrideProfileId = nil
        manualOverrideDate = nil
        saveOverrideState()

        // Revert to scheduled profile if available
        if let scheduledProfile = profileForDay(.today) {
            activateProfile(id: scheduledProfile.id, reason: .scheduled)
        }
    }

    // MARK: - Scheduling

    func checkForScheduledSwitch() {
        // If manual override is active and still valid, don't switch
        if isManualOverrideActive {
            return
        }

        // Clear expired override
        if manualOverrideDate != nil, !isManualOverrideActive {
            manualOverrideProfileId = nil
            manualOverrideDate = nil
            saveOverrideState()
        }

        // Check if we already switched today
        if let lastSwitch = lastSwitchDate,
           Calendar.current.isDateInToday(lastSwitch)
        {
            return
        }

        // Find profile for today
        guard let scheduledProfile = profileForDay(.today) else {
            return
        }

        // Check if we need to switch
        if activeProfile?.id != scheduledProfile.id {
            lastSwitchDate = Date()
            activateProfile(id: scheduledProfile.id, reason: .scheduled)
        }
    }

    func profileForDay(_ weekday: Weekday) -> TherapyProfile? {
        profiles.first { $0.activeDays.contains(weekday) }
    }

    // MARK: - Notifications

    func acknowledgeSwitchNotification() {
        if var notification = pendingSwitchNotification {
            notification.acknowledged = true
            // Update in history
            if let index = switchHistory.firstIndex(where: { $0.id == notification.id }) {
                switchHistory[index] = notification
                saveSwitchHistory()
            }
        }
        pendingSwitchNotification = nil
    }

    // MARK: - Migration

    func migrateFromSingleProfile() {
        debug(.service, "Migrating from single profile system...")

        // Load existing settings
        let basalProfile = storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self) ?? []
        let insulinSensitivities = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
        let carbRatios = storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
        let bgTargets = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)

        let units = settingsManager.settings.units

        // Create default profile with all existing settings
        let defaultProfile = TherapyProfile(
            name: NSLocalizedString("Default", comment: "Default profile name"),
            activeDays: Weekday.allDays,
            basalProfile: basalProfile,
            insulinSensitivities: insulinSensitivities ?? InsulinSensitivities(
                units: units,
                userPreferredUnits: units,
                sensitivities: []
            ),
            carbRatios: carbRatios ?? CarbRatios(units: .grams, schedule: []),
            bgTargets: bgTargets ?? BGTargets(
                units: units,
                userPreferredUnits: units,
                targets: []
            ),
            isDefault: true
        )

        profiles = [defaultProfile]
        activeProfile = defaultProfile
        saveProfiles()
        saveActiveProfileId(defaultProfile.id)

        debug(.service, "Migration complete - created default profile")
    }

    // MARK: - Private Methods

    private func loadProfiles() {
        profiles = storage.retrieve(OpenAPS.Trio.therapyProfiles, as: [TherapyProfile].self) ?? []
    }

    private func saveProfiles() {
        storage.save(profiles, as: OpenAPS.Trio.therapyProfiles)
    }

    private func loadActiveProfile() {
        guard let activeIdString = storage.retrieve(OpenAPS.Trio.activeProfileId, as: String.self),
              let activeId = UUID(uuidString: activeIdString)
        else {
            // Default to the default profile or first profile
            activeProfile = profiles.first { $0.isDefault } ?? profiles.first
            if let profile = activeProfile {
                saveActiveProfileId(profile.id)
            }
            return
        }

        activeProfile = profiles.first { $0.id == activeId }

        // Fallback if active profile not found
        if activeProfile == nil {
            activeProfile = profiles.first { $0.isDefault } ?? profiles.first
            if let profile = activeProfile {
                saveActiveProfileId(profile.id)
            }
        }
    }

    private func saveActiveProfileId(_ id: UUID) {
        storage.save(id.uuidString, as: OpenAPS.Trio.activeProfileId)
    }

    private func loadSwitchHistory() {
        switchHistory = storage.retrieve(OpenAPS.Trio.profileSwitchHistory, as: [ProfileSwitchEvent].self) ?? []
    }

    private func saveSwitchHistory() {
        storage.save(switchHistory, as: OpenAPS.Trio.profileSwitchHistory)
    }

    private func loadOverrideState() {
        // Override state is stored in TrioSettings
        // For now, we'll use a simple approach - could be enhanced later
    }

    private func saveOverrideState() {
        // Override state persistence
    }

    /// Writes the profile's therapy settings to the individual OpenAPS settings files.
    /// This maintains compatibility with the existing OpenAPS algorithm.
    private func writeProfileSettingsToFiles(_ profile: TherapyProfile) {
        storage.save(profile.basalProfile, as: OpenAPS.Settings.basalProfile)
        storage.save(profile.insulinSensitivities, as: OpenAPS.Settings.insulinSensitivities)
        storage.save(profile.carbRatios, as: OpenAPS.Settings.carbRatios)
        storage.save(profile.bgTargets, as: OpenAPS.Settings.bgTargets)

        // Notify observers of the individual setting changes
        broadcaster.notify(BasalProfileObserver.self, on: .main) {
            $0.basalProfileDidChange(profile.basalProfile)
        }
        broadcaster.notify(BGTargetsObserver.self, on: .main) {
            $0.bgTargetsDidChange(profile.bgTargets)
        }
    }

    private func notifyActiveProfileChanged(_ profile: TherapyProfile) {
        broadcaster.notify(ProfileManagerObserver.self, on: .main) {
            $0.activeProfileDidChange(profile)
        }
        broadcaster.notify(TherapyProfileObserver.self, on: .main) {
            $0.activeProfileDidChange(profile)
        }
    }

    private func notifyProfilesChanged() {
        broadcaster.notify(ProfileManagerObserver.self, on: .main) {
            $0.profilesDidChange(self.profiles)
        }
    }
}
