import CoreData
import Foundation

/// Portable configuration, preset templates, and historical TDD summaries.
/// Excludes credentials, device pairing, active delivery state, and treatment events.
struct TrioSettingsBackup: Codable {
    static let currentSchema = 5
    static let maximumSize = 8 * 1024 * 1024

    enum Origin: String, Codable, CaseIterable, Hashable {
        case automatic
        case manual
    }

    let schemaVersion: Int
    let id: UUID
    let createdAt: Date
    let appVersion: String
    let origin: Origin
    var name: String?
    let configuration: Configuration
    let fingerprint: String
    var dynamicISFHistory: [TDDRecord]? = nil
    var historyChecksum: String? = nil

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case createdAt
        case appVersion
        case origin
        case name
        case configuration
        case fingerprint
        case dynamicISFHistory
        case historyChecksum
    }

    /// Configuration fingerprint excludes Dynamic ISF history.
    func cloudFingerprint() throws -> String { fingerprint }

    struct Configuration: Codable {
        var settings: TrioSettings
        var preferences: Preferences
        var pumpSettings: PumpSettings
        var basalProfile: [BasalProfileEntry]
        var carbRatios: CarbRatios
        var insulinSensitivities: InsulinSensitivities
        var glucoseTargets: BGTargets
        var presets: Presets
        // Absent only in schema 2, which predates portable alert/display settings.
        var appConfiguration: AppConfiguration? = nil

        private enum CodingKeys: String, CodingKey {
            case settings
            case preferences
            case pumpSettings
            case basalProfile
            case carbRatios
            case insulinSensitivities
            case glucoseTargets
            case presets
            case appConfiguration
        }

        init(from decoder: Decoder) throws {
            try self.init(from: decoder, legacySettings: nil)
        }

        init(from decoder: Decoder, legacySettings: Bool?) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let settingsDecoder = try values.superDecoder(forKey: .settings)
            let original = try BackupJSONValue(from: settingsDecoder)
            guard case let .object(fields) = original else { throw BackupError.invalidTherapyConfiguration }
            if legacySettings ?? (fields["dosingMode"] != nil) {
                settings = try BackupStrict<TrioSettings>(from: settingsDecoder).value
            } else {
                settings = try BackupPortableSettings(from: settingsDecoder).value
            }
            preferences = try values.decode(BackupStrict<Preferences>.self, forKey: .preferences).value
            pumpSettings = try values.decode(PumpSettings.self, forKey: .pumpSettings)
            basalProfile = try values.decode([BasalProfileEntry].self, forKey: .basalProfile)
            carbRatios = try values.decode(CarbRatios.self, forKey: .carbRatios)
            insulinSensitivities = try values.decode(InsulinSensitivities.self, forKey: .insulinSensitivities)
            glucoseTargets = try values.decode(BGTargets.self, forKey: .glucoseTargets)
            presets = try values.decode(Presets.self, forKey: .presets)
            appConfiguration = try values.decodeIfPresent(BackupStrict<AppConfiguration>.self, forKey: .appConfiguration)?.value
        }

        func encode(to encoder: Encoder) throws {
            try encode(to: encoder, legacySettings: false)
        }

        func encode(to encoder: Encoder, legacySettings: Bool) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            if legacySettings { try values.encode(settings, forKey: .settings) }
            else { try values.encode(BackupPortableSettings(value: settings), forKey: .settings) }
            try values.encode(preferences, forKey: .preferences)
            try values.encode(pumpSettings, forKey: .pumpSettings)
            try values.encode(basalProfile, forKey: .basalProfile)
            try values.encode(carbRatios, forKey: .carbRatios)
            try values.encode(insulinSensitivities, forKey: .insulinSensitivities)
            try values.encode(glucoseTargets, forKey: .glucoseTargets)
            try values.encode(presets, forKey: .presets)
            try values.encodeIfPresent(appConfiguration, forKey: .appConfiguration)
        }

        init(
            settings: TrioSettings,
            preferences: Preferences,
            pumpSettings: PumpSettings,
            basalProfile: [BasalProfileEntry],
            carbRatios: CarbRatios,
            insulinSensitivities: InsulinSensitivities,
            glucoseTargets: BGTargets,
            presets: Presets,
            appConfiguration: AppConfiguration? = nil
        ) {
            self.settings = settings
            self.preferences = preferences
            self.pumpSettings = pumpSettings
            self.basalProfile = basalProfile
            self.carbRatios = carbRatios
            self.insulinSensitivities = insulinSensitivities
            self.glucoseTargets = glucoseTargets
            self.presets = presets
            self.appConfiguration = appConfiguration
        }
    }

    struct AppConfiguration: Codable {
        let appearance: ColorSchemeOption
        let liveActivityOrder: [String]?
        var glucoseAlerts: [GlucoseAlert]
        let glucoseAlertConfiguration: GlucoseAlertConfiguration
        var deviceAlertConfigurations: [DeviceAlertSeverityConfig]

        static let keys = [
            "colorSchemePreference",
            "liveActivityOrder",
            "trio.glucoseAlerts.v1",
            "trio.glucoseAlertConfiguration.v1",
            "trio.deviceAlertSeverityConfigs.v1"
        ]

        static func capture(defaults: UserDefaults = .standard) -> Self {
            // Stores own the effective saved configuration. Never include snoozes.
            var alerts = GlucoseAlertsStore.shared.alerts
            for index in alerts.indices { alerts[index].snoozedUntil = nil }
            return Self(
                appearance: ColorSchemeOption(rawValue: defaults.string(forKey: keys[0]) ?? "") ?? .systemDefault,
                liveActivityOrder: defaults.stringArray(forKey: keys[1]),
                glucoseAlerts: alerts,
                glucoseAlertConfiguration: GlucoseAlertsStore.shared.configuration,
                deviceAlertConfigurations: DeviceAlertsStore.shared.configs
            )
        }

        func apply(defaults: UserDefaults = .standard) throws {
            // Encode before mutating anything; the restore journal includes all keys.
            let alerts = try JSONEncoder().encode(glucoseAlerts)
            let config = try JSONEncoder().encode(glucoseAlertConfiguration)
            let devices = try JSONEncoder().encode(deviceAlertConfigurations)
            defaults.set(appearance.rawValue, forKey: Self.keys[0])
            defaults.set(liveActivityOrder, forKey: Self.keys[1])
            defaults.set(alerts, forKey: Self.keys[2])
            defaults.set(config, forKey: Self.keys[3])
            defaults.set(devices, forKey: Self.keys[4])
            GlucoseAlertsStore.shared.alerts = glucoseAlerts
            GlucoseAlertsStore.shared.configuration = glucoseAlertConfiguration
            DeviceAlertsStore.shared.configs = deviceAlertConfigurations
            Foundation.NotificationCenter.default.post(name: .liveActivityOrderDidChange, object: nil)
        }
    }

    /// Saved templates only; active adjustments and treatment history are excluded.
    struct Presets: Codable {
        let overrides: [OverridePreset]
        let tempTargets: [TempTargetPreset]
        let meals: [MealPreset]
    }

    struct OverridePreset: Codable {
        let name: String?
        let order: Int16
        let percentage: Double
        let duration: Decimal?
        let indefinite: Bool
        var target: Decimal?
        let isf: Bool
        let cr: Bool
        let isfAndCr: Bool
        let advancedSettings: Bool
        let smbIsScheduledOff: Bool
        let smbIsOff: Bool
        let smbMinutes: Decimal?
        let uamMinutes: Decimal?
        let start: Decimal?
        let end: Decimal?
    }

    struct TempTargetPreset: Codable {
        let name: String?
        let order: Int16
        let duration: Decimal?
        let target: Decimal?
        let halfBasalTarget: Decimal?
    }

    struct MealPreset: Codable {
        let dish: String?
        let carbs: Decimal?
        let fat: Decimal?
        let protein: Decimal?
    }

    static func readPresets(context: NSManagedObjectContext = CoreDataStack.shared.newTaskContext()) async throws -> Presets {
        try await context.perform {
            let overridesRequest = OverrideStored.fetchRequest()
            overridesRequest.predicate = NSPredicate(format: "isPreset == YES")
            let tempTargetsRequest = TempTargetStored.fetchRequest()
            tempTargetsRequest.predicate = NSPredicate(format: "isPreset == YES")
            let overrides = try context.fetch(overridesRequest).map { preset in
                OverridePreset(
                    name: preset.name, order: preset.orderPosition,
                    percentage: preset.percentage, duration: preset.duration?.decimalValue,
                    indefinite: preset.indefinite, target: preset.target?.decimalValue,
                    isf: preset.isf, cr: preset.cr, isfAndCr: preset.isfAndCr,
                    advancedSettings: preset.advancedSettings,
                    smbIsScheduledOff: preset.smbIsScheduledOff,
                    smbIsOff: preset.smbIsOff,
                    smbMinutes: preset.smbMinutes?.decimalValue,
                    uamMinutes: preset.uamMinutes?.decimalValue,
                    start: preset.start?.decimalValue, end: preset.end?.decimalValue
                )
            }
            let targets = try context.fetch(tempTargetsRequest).map { preset in
                TempTargetPreset(
                    name: preset.name, order: preset.orderPosition,
                    duration: preset.duration?.decimalValue,
                    target: preset.target?.decimalValue,
                    halfBasalTarget: preset.halfBasalTarget?.decimalValue
                )
            }
            let meals = try context.fetch(MealPresetStored.fetchRequest()).map { preset in
                MealPreset(
                    dish: preset.dish, carbs: preset.carbs?.decimalValue,
                    fat: preset.fat?.decimalValue, protein: preset.protein?.decimalValue
                )
            }
            return Presets(
                overrides: try stableSort(overrides),
                tempTargets: try stableSort(targets),
                meals: try stableSort(meals)
            )
        }
    }

    @MainActor static func capture(
        storage: FileStorage,
        origin: Origin,
        name: String? = nil
    ) async throws -> TrioSettingsBackup {
        let capturedAt = Date()
        let presets = try await readPresets()
        let history = try await readTDDHistory(now: capturedAt)
        let appConfiguration = AppConfiguration.capture()
        var capturedConfiguration: Configuration?
        // Read the saved source files together, never generated profiles/autotune.
        storage.transaction { storage in
            guard let settings = storage.retrieve(OpenAPS.Trio.settings, as: TrioSettings.self),
                  let preferences = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self),
                  let basal = storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self),
                  let carbs = storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self),
                  let isf = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self),
                  let targets = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self),
                  let pump = storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
            else { return }
            capturedConfiguration = Configuration(
                settings: settings, preferences: preferences, pumpSettings: pump,
                basalProfile: basal, carbRatios: carbs, insulinSensitivities: isf,
                glucoseTargets: targets, presets: presets,
                appConfiguration: appConfiguration
            )
        }
        guard let saved = capturedConfiguration else { throw BackupError.incompleteConfiguration }
        let configuration = try normalized(saved)
        try validate(configuration)
        let trimmedName = normalizedName(name)
        return TrioSettingsBackup(
            schemaVersion: currentSchema,
            id: UUID(),
            createdAt: capturedAt,
            appVersion: "\(Bundle.main.appDevVersion ?? "Unknown") (\(Bundle.main.buildVersionNumber ?? "Unknown"))",
            origin: origin,
            name: trimmedName,
            configuration: configuration,
            fingerprint: try Self.normalizedFingerprint(configuration),
            dynamicISFHistory: history, historyChecksum: try Self.historyDigest(history)
        )
    }

}

extension TrioSettingsBackup {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard (2 ... Self.currentSchema).contains(schemaVersion) else { throw BackupError.unsupportedSchema }
        id = try values.decode(UUID.self, forKey: .id)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        appVersion = try values.decode(String.self, forKey: .appVersion)
        origin = try values.decode(Origin.self, forKey: .origin)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        configuration = try Configuration(
            from: values.superDecoder(forKey: .configuration), legacySettings: schemaVersion < 5
        )
        fingerprint = try values.decode(String.self, forKey: .fingerprint)
        dynamicISFHistory = try values.decodeIfPresent([TDDRecord].self, forKey: .dynamicISFHistory)
        historyChecksum = try values.decodeIfPresent(String.self, forKey: .historyChecksum)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(appVersion, forKey: .appVersion)
        try values.encode(origin, forKey: .origin)
        try values.encodeIfPresent(name, forKey: .name)
        try configuration.encode(to: values.superEncoder(forKey: .configuration), legacySettings: schemaVersion < 5)
        try values.encode(fingerprint, forKey: .fingerprint)
        try values.encodeIfPresent(dynamicISFHistory, forKey: .dynamicISFHistory)
        try values.encodeIfPresent(historyChecksum, forKey: .historyChecksum)
    }
}

struct LegacyBackupConfiguration: Encodable {
    let value: TrioSettingsBackup.Configuration
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder, legacySettings: true) }
}

enum BackupError: LocalizedError, Equatable {
    case backupTooLarge
    case incompleteConfiguration
    case invalidTherapyConfiguration
    case unsupportedSchema
    case integrityCheckFailed
    case iCloudUnavailable
    case invalidCloudRecord
    case notOnboarding
    case activeAdjustments
    case operationInProgress
    case restoreFailed
    case pumpNotReady
    case incompatiblePumpSettings
    case backupNameRequired
    case invalidRetentionLimit

    var errorDescription: String? {
        switch self {
        case .backupNameRequired: return "Enter a name for your backup."
        case .invalidRetentionLimit: return "Choose a backup limit of 3, 5, 10, or 15."
        case .backupTooLarge: return "This backup is too large. The limit is 8 MB."
        case .incompleteConfiguration: return "Complete your therapy settings before creating a backup."
        case .invalidTherapyConfiguration: return "This backup has invalid therapy settings and cannot be restored."
        case .unsupportedSchema: return "Update Trio to open this backup."
        case .integrityCheckFailed: return "This backup is damaged and cannot be restored."
        case .iCloudUnavailable: return "Sign in to iCloud in iPhone Settings and enable iCloud for Trio."
        case .invalidCloudRecord: return "The iCloud backup could not be read."
        case .notOnboarding: return "This restore operation is not available during the current setup state."
        case .activeAdjustments: return "Disable all running overrides and temporary targets before restoring settings."
        case .operationInProgress: return "Trio is busy. Wait for the current operation to finish, then try again."
        case .restoreFailed: return "Restore failed. Trio is in Open Loop. Check your settings and pump delivery."
        case .pumpNotReady: return "Restore stopped because pump delivery could not be safely suspended. Check your pump before trying again."
        case .incompatiblePumpSettings: return "This backup’s insulin concentration, basal rates, or delivery limits do not match your pump. Settings were not restored."
        }
    }
}

