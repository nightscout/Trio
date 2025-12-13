import Combine
import Foundation
import Swinject

/// Protocol for managing therapy profiles with scheduled switching.
protocol ProfileManager: AnyObject {
    // MARK: - Properties

    /// All therapy profiles
    var profiles: [TherapyProfile] { get }

    /// The currently active therapy profile
    var activeProfile: TherapyProfile? { get }

    /// Publisher for active profile changes
    var activeProfilePublisher: AnyPublisher<TherapyProfile?, Never> { get }

    /// Pending switch notification to be displayed to user
    var pendingSwitchNotification: ProfileSwitchEvent? { get set }

    /// Publisher for pending switch notifications
    var pendingSwitchNotificationPublisher: AnyPublisher<ProfileSwitchEvent?, Never> { get }

    /// History of profile switch events
    var switchHistory: [ProfileSwitchEvent] { get }

    /// Whether a manual override is currently active for today
    var isManualOverrideActive: Bool { get }

    /// The ID of the manually overridden profile (if any)
    var manualOverrideProfileId: UUID? { get }

    /// The date when the manual override was set
    var manualOverrideDate: Date? { get }

    // MARK: - Profile Management

    /// Creates a new profile, optionally copying settings from an existing profile.
    /// - Parameters:
    ///   - name: The name for the new profile
    ///   - copyFrom: Optional profile to copy settings from
    /// - Returns: The newly created profile
    func createProfile(name: String, copyFrom: TherapyProfile?) -> TherapyProfile

    /// Updates an existing profile.
    /// - Parameter profile: The profile with updated values
    func updateProfile(_ profile: TherapyProfile)

    /// Deletes a profile by ID.
    /// - Parameter id: The ID of the profile to delete
    /// - Throws: ProfileManagerError if the profile cannot be deleted
    func deleteProfile(id: UUID) throws

    // MARK: - Activation

    /// Activates a profile by ID.
    /// - Parameters:
    ///   - id: The ID of the profile to activate
    ///   - reason: The reason for the switch
    func activateProfile(id: UUID, reason: ProfileSwitchEvent.SwitchReason)

    /// Activates a profile as a manual override for the current day.
    /// This overrides the scheduled profile until midnight.
    /// - Parameter id: The ID of the profile to activate
    func activateProfileAsOverride(id: UUID)

    /// Clears any manual override, reverting to the scheduled profile.
    func clearManualOverride()

    // MARK: - Scheduling

    /// Checks if a scheduled profile switch should occur and performs it.
    /// Called from the main loop at regular intervals.
    func checkForScheduledSwitch()

    /// Returns the profile assigned to a specific day.
    /// - Parameter weekday: The day of week
    /// - Returns: The profile assigned to that day, or nil if none
    func profileForDay(_ weekday: Weekday) -> TherapyProfile?

    // MARK: - Notifications

    /// Acknowledges and dismisses the pending switch notification.
    func acknowledgeSwitchNotification()

    // MARK: - Migration

    /// Migrates from the single-profile system to the multi-profile system.
    /// Called on app startup if no profiles exist.
    func migrateFromSingleProfile()
}

/// Errors that can occur during profile management operations.
enum ProfileManagerError: LocalizedError {
    case cannotDeleteDefaultProfile
    case cannotDeleteActiveProfile
    case profileNotFound
    case maximumProfilesReached
    case profileNameExists

    var errorDescription: String? {
        switch self {
        case .cannotDeleteDefaultProfile:
            return NSLocalizedString("Cannot delete the default profile", comment: "Error message")
        case .cannotDeleteActiveProfile:
            return NSLocalizedString("Cannot delete the currently active profile", comment: "Error message")
        case .profileNotFound:
            return NSLocalizedString("Profile not found", comment: "Error message")
        case .maximumProfilesReached:
            return NSLocalizedString("Maximum number of profiles reached", comment: "Error message")
        case .profileNameExists:
            return NSLocalizedString("A profile with this name already exists", comment: "Error message")
        }
    }
}

/// Observer protocol for profile change notifications.
protocol ProfileManagerObserver {
    func activeProfileDidChange(_ profile: TherapyProfile)
    func profilesDidChange(_ profiles: [TherapyProfile])
}

extension ProfileManagerObserver {
    func activeProfileDidChange(_ profile: TherapyProfile) {}
    func profilesDidChange(_ profiles: [TherapyProfile]) {}
}
