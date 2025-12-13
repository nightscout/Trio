# Therapy Profiles Implementation Plan

## Overview

Implement weekday/weekend therapy profiles for Trio, allowing users to create multiple named therapy profiles with different settings that automatically switch based on the day of week.

## Requirements

1. **Multiple Profiles**: Up to 10 named therapy profiles
2. **Complete Settings Per Profile**:
   - Basal rates
   - Insulin Sensitivity Factors (ISF)
   - Carb Ratios
   - Glucose Targets
3. **Day Assignment**: User-selectable days of the week per profile
4. **Automatic Switching**: Profile switches at midnight based on day of week
5. **Manual Override**: Ability to manually activate a different profile for the current day
6. **Notifications**: In-app banner when profile switches (not push notifications)
7. **History Logging**: Log all profile switches with timestamps and reasons
8. **Nightscout Sync**: Sync profile changes to Nightscout
9. **No Watch App**: Watch integration not required at this time

## Architecture

### Directory Structure (Trio v0.6.0)

```
Trio/Sources/
├── Models/
│   ├── Weekday.swift                    # Days of week enum
│   ├── TherapyProfile.swift             # Profile model with all settings
│   └── ProfileSwitchEvent.swift         # Switch history event
├── Services/
│   └── ProfileManager/
│       ├── ProfileManager.swift         # Protocol
│       └── BaseProfileManager.swift     # Implementation
├── Modules/
│   ├── TherapyProfileList/
│   │   ├── TherapyProfileListDataFlow.swift
│   │   ├── TherapyProfileListProvider.swift
│   │   ├── TherapyProfileListStateModel.swift
│   │   └── View/
│   │       └── TherapyProfileListRootView.swift
│   └── TherapyProfileEditor/
│       ├── TherapyProfileEditorDataFlow.swift
│       ├── TherapyProfileEditorProvider.swift
│       ├── TherapyProfileEditorStateModel.swift
│       └── View/
│           └── TherapyProfileEditorRootView.swift
└── Views/
    ├── WeekdayPickerView.swift          # Multi-select day picker
    └── ProfileSwitchBannerView.swift    # Switch notification banner
```

### Storage Files

```
settings/
├── therapy_profiles.json       # Array of TherapyProfile
├── active_profile_id.json      # UUID string of active profile
└── profile_switch_history.json # Array of ProfileSwitchEvent
```

## Data Models

### Weekday
```swift
enum Weekday: Int, CaseIterable, Codable, Comparable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    static var today: Weekday
    static var weekdays: Set<Weekday>  // Mon-Fri
    static var weekend: Set<Weekday>   // Sat-Sun

    var localizedName: String
    var shortName: String
}
```

### TherapyProfile
```swift
struct TherapyProfile: JSON, Identifiable, Equatable {
    let id: UUID
    var name: String
    var activeDays: Set<Weekday>
    var basalProfile: [BasalProfileEntry]
    var insulinSensitivities: InsulinSensitivities
    var carbRatios: CarbRatios
    var bgTargets: BGTargets
    var isDefault: Bool
    var createdAt: Date
    var lastModified: Date

    static let maxProfiles = 10
}
```

### ProfileSwitchEvent
```swift
struct ProfileSwitchEvent: JSON, Identifiable, Equatable {
    let id: UUID
    let fromProfileId: UUID?
    let fromProfileName: String?
    let toProfileId: UUID
    let toProfileName: String
    let switchedAt: Date
    let weekday: Weekday
    let reason: SwitchReason
    var acknowledged: Bool

    enum SwitchReason: String, Codable {
        case scheduled      // Automatic midnight switch
        case manual         // User activated profile
        case manualOverride // User overrode scheduled profile for today
    }
}
```

## ProfileManager Protocol

```swift
protocol ProfileManager: AnyObject {
    // Properties
    var profiles: [TherapyProfile] { get }
    var activeProfile: TherapyProfile { get }
    var activeProfilePublisher: AnyPublisher<TherapyProfile, Never> { get }
    var pendingSwitchNotification: ProfileSwitchEvent? { get set }
    var pendingSwitchNotificationPublisher: AnyPublisher<ProfileSwitchEvent?, Never> { get }
    var switchHistory: [ProfileSwitchEvent] { get }
    var isManualOverrideActive: Bool { get }

    // Profile Management
    func createProfile(name: String, copyFrom: TherapyProfile?) -> TherapyProfile
    func updateProfile(_ profile: TherapyProfile)
    func deleteProfile(id: UUID) throws

    // Activation
    func activateProfile(id: UUID, reason: ProfileSwitchEvent.SwitchReason)
    func activateProfileAsOverride(id: UUID)
    func clearManualOverride()

    // Scheduling
    func checkForScheduledSwitch()
    func profileForDay(_ weekday: Weekday) -> TherapyProfile?

    // Notifications
    func acknowledgeSwitchNotification()
}
```

## Key Implementation Details

### Migration from Single Profile

When user first opens app after update:
1. Check if `therapy_profiles.json` exists
2. If not, create default profile from existing settings files:
   - `basal_profile.json`
   - `insulin_sensitivities.json`
   - `carb_ratios.json`
   - `bg_targets.json`
3. Mark as default profile, assign all days

### Day Uniqueness

- Each day can only be assigned to ONE profile
- When assigning a day to profile A, automatically remove it from profile B
- UI shows conflicts/warnings before saving

### Midnight Switching Logic

Called from the main loop (`APSManager`):
1. Check if manual override is active and still valid (same day)
2. If override expired, clear it
3. Check if already switched today
4. Find profile assigned to current weekday
5. If different from active, switch and log event

### Profile Activation Flow

1. Save active profile ID
2. Write settings to individual files (for OpenAPS compatibility):
   - `basal_profile.json`
   - `insulin_sensitivities.json`
   - `carb_ratios.json`
   - `bg_targets.json`
3. Create switch event
4. Notify observers
5. Set pending notification for banner

### In-App Banner

- Shown when app enters foreground after a switch
- Auto-dismisses after 8 seconds
- Shows "Profile switched to [name]" with reason
- Dismiss button for immediate dismissal

## UI Flow

### Settings Menu
```
Settings
└── Configuration
    └── Therapy Profiles  →  TherapyProfileListRootView
```

### Profile List View
- List of all profiles with active indicator
- Tap to edit
- Swipe to delete (except default/active)
- "Add Profile" button (if < 10)
- "Activate" button per profile
- "Override for Today" option

### Profile Editor View
- Name field
- Day picker (multi-select with conflict warnings)
- Sections for each setting type:
  - Basal Rates → existing editor
  - ISF → existing editor
  - Carb Ratios → existing editor
  - Glucose Targets → existing editor
- "Set as Default" toggle
- Save/Cancel buttons

## Validation Rules

1. Profile name must be unique and non-empty
2. Default profile cannot be deleted
3. Active profile cannot be deleted
4. At least one profile must exist
5. Maximum 10 profiles
6. Days are automatically deduplicated across profiles

## Files to Modify

1. **Trio/Sources/APS/OpenAPS/Constants.swift** - Add file paths
2. **Trio/Sources/Assemblies/StorageAssembly.swift** - Register ProfileManager
3. **Trio/Sources/APS/APSManager.swift** - Add profile switch check in loop
4. **Trio/Sources/Router/Screen.swift** - Add new screen cases
5. **Trio/Sources/Modules/Settings/View/SettingsRootView.swift** - Add menu entry
6. **Trio/Sources/Modules/Home/HomeStateModel.swift** - Subscribe to profile notifications
7. **Trio/Sources/Modules/Home/View/HomeRootView.swift** - Add banner overlay
8. **Trio.xcodeproj/project.pbxproj** - Add all new files

## Testing Checklist

- [ ] Create profile with all settings
- [ ] Edit profile name and days
- [ ] Delete non-active profile
- [ ] Verify cannot delete active/default profile
- [ ] Automatic midnight switch (simulate by changing date)
- [ ] Manual profile activation
- [ ] Manual override for today
- [ ] Banner appears on foreground after switch
- [ ] Banner auto-dismisses
- [ ] History logging accurate
- [ ] Migration from single profile system
- [ ] Day uniqueness enforced
- [ ] Profile limit enforced (max 10)

## Nightscout Integration

Profile switches will be synced to Nightscout as:
- Profile switch treatment entries
- Updated profile store with all therapy profiles

## Future Considerations

- Watch app support
- Time-based switching (not just day-based)
- Profile scheduling calendar view
- Profile import/export
