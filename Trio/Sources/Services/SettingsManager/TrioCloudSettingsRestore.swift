import CoreData
import CryptoKit
import Foundation

/// Restore settings and Dynamic ISF history only while no pump is paired.
/// A rollback journal protects settings files, presets and history across a crash.
enum TrioCloudSettingsRestore {
    @MainActor private static var restoring = false
    @MainActor static var isRestoring: Bool { restoring }
    static let pumpRecoveryKey = "trio.cloudRestore.pumpReconciliationPending"
    static let rollbackFileName = ".trio-cloud-rollback.json"
    static let journalFileName = ".trio-cloud-restore-journal.json"
    static let names = [
        OpenAPS.Trio.settings, OpenAPS.Settings.preferences,
        OpenAPS.Settings.settings, OpenAPS.Settings.basalProfile,
        OpenAPS.Settings.carbRatios, OpenAPS.Settings.insulinSensitivities,
        OpenAPS.Settings.bgTargets
    ]

    static func configurationFiles(_ value: TrioSettingsBackup.Configuration) throws -> [(String, Data)] {
        try [
            (OpenAPS.Trio.settings, JSONCoding.encoder.encode(value.settings)),
            (OpenAPS.Settings.preferences, JSONCoding.encoder.encode(value.preferences)),
            (OpenAPS.Settings.settings, JSONCoding.encoder.encode(value.pumpSettings)),
            (OpenAPS.Settings.basalProfile, JSONCoding.encoder.encode(value.basalProfile)),
            (OpenAPS.Settings.carbRatios, JSONCoding.encoder.encode(value.carbRatios)),
            (OpenAPS.Settings.insulinSensitivities, JSONCoding.encoder.encode(value.insulinSensitivities)),
            (OpenAPS.Settings.bgTargets, JSONCoding.encoder.encode(value.glucoseTargets))
        ]
    }

    struct PreviousFile: Codable {
        let name: String
        let contents: Data?
    }

    struct Journal: Codable {
        let files: [PreviousFile]
        let presets: TrioSettingsBackup.Presets
        var defaults: [String: Data]? = nil
        var checksum: String? = nil
        var insertedTDDIDs: [UUID]? = nil
        var requiresPumpReconciliation: Bool? = nil

        private func digest() throws -> String {
            var unsigned = self
            unsigned.checksum = nil
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return SHA256.hash(data: try encoder.encode(unsigned)).map { String(format: "%02x", $0) }.joined()
        }

        func sealed() throws -> Self {
            var value = self
            value.checksum = try digest()
            return value
        }

        func verify() throws {
            // Older in-progress journals were written without a checksum.
            if let checksum, checksum != (try digest()) { throw BackupError.integrityCheckFailed }
        }
    }

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    @MainActor static func applyDuringOnboarding(
        _ candidate: TrioSettingsBackup, settingsManager: SettingsManager, deviceManager: DeviceDataManager
    ) async throws {
        guard OnboardingManager.shared.shouldShowOnboarding else { throw BackupError.notOnboarding }
        try await apply(candidate, settingsManager: settingsManager, deviceManager: deviceManager, onboarding: true)
    }

    @MainActor static func applyConfigured(
        _ candidate: TrioSettingsBackup, settingsManager: SettingsManager, deviceManager: DeviceDataManager
    ) async throws {
        guard !OnboardingManager.shared.shouldShowOnboarding else { throw BackupError.notOnboarding }
        try await apply(candidate, settingsManager: settingsManager, deviceManager: deviceManager, onboarding: false)
    }

    @MainActor private static func apply(
        _ candidate: TrioSettingsBackup,
        settingsManager: SettingsManager,
        deviceManager: DeviceDataManager,
        onboarding: Bool
    ) async throws {
        // Restoration requires an unpaired pump and must never mutate pump hardware.
        guard deviceManager.pumpManager == nil else { throw BackupError.pumpNotReady }
        guard !restoring, !TrioCloudBackupCoordinator.shared.isUploading else {
            throw BackupError.operationInProgress
        }
        restoring = true
        defer { restoring = false }
        let snapshot = try candidate.validated()
        let previousSettings = settingsManager.settings
        let previousPreferences = settingsManager.preferences
        let proposed = try TrioSettingsBackup.normalized(snapshot.configuration)
        let safe = onboarding
            ? try onboardingConfiguration(proposed)
            : configuredConfiguration(proposed, currentSettings: previousSettings, currentPreferences: previousPreferences)
        do {
            try await performTransaction(
                newFiles: configurationFiles(safe),
                presets: safe.presets,
                directory: documents,
                tddHistory: snapshot.eligibleTDDHistory(),
                preflight: {
                    guard deviceManager.pumpManager == nil else { throw BackupError.pumpNotReady }
                    if onboarding && !OnboardingManager.shared.shouldShowOnboarding {
                        throw BackupError.notOnboarding
                    }
                },
                prepareHardware: {
                    // Never reactivate delivery. Open Loop is persisted first.
                    settingsManager.settings = try persistOpenLoop(previousSettings)
                },
                synchronizeCache: {
                    try safe.appConfiguration?.apply()
                    settingsManager.settings = safe.settings
                    settingsManager.preferences = safe.preferences
                },
                verifyConfiguration: {
                    guard deviceManager.pumpManager == nil,
                          settingsManager.settings == safe.settings
                    else { throw BackupError.restoreFailed }
                    if let app = safe.appConfiguration {
                        guard try canonical(app) == canonical(TrioSettingsBackup.AppConfiguration.capture())
                        else { throw BackupError.restoreFailed }
                    }
                }
            )
            await CoreDataStack.shared.fetchPersistentHistory()
        } catch {
            do {
                try await recoverInterruptedRestoreIfNeeded()
                settingsManager.settings = try persistOpenLoop(previousSettings)
                settingsManager.preferences = previousPreferences
                GlucoseAlertsStore.shared.reloadSavedConfiguration()
                DeviceAlertsStore.shared.reloadSavedConfiguration()
            } catch { throw BackupError.restoreFailed }
            throw error
        }
    }

    /// Fresh installations may not have created the nested settings directory yet.
    static func persistOpenLoop(_ source: TrioSettings, directory: URL? = nil) throws -> TrioSettings {
        var settings = source
        settings.dosingMode = .open
        let url = (directory ?? documents).appendingPathComponent(OpenAPS.Trio.settings)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONCoding.encoder.encode(settings).write(to: url, options: [.atomic, .completeFileProtection])
        return settings
    }

    @MainActor private static func savedConfiguration(
        settings: TrioSettings,
        preferences: Preferences
    ) async throws -> TrioSettingsBackup
        .Configuration
    {
        func read<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
            try JSONCoding.decoder.decode(type, from: Data(contentsOf: documents.appendingPathComponent(name)))
        }
        return try await .init(
            settings: settings,
            preferences: preferences,
            pumpSettings: read(OpenAPS.Settings.settings, as: PumpSettings.self),
            basalProfile: read(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self),
            carbRatios: read(OpenAPS.Settings.carbRatios, as: CarbRatios.self),
            insulinSensitivities: read(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self),
            glucoseTargets: read(OpenAPS.Settings.bgTargets, as: BGTargets.self),
            presets: TrioSettingsBackup.readPresets(),
            appConfiguration: TrioSettingsBackup.AppConfiguration.capture()
        )
    }

    static func configuredConfiguration(
        _ source: TrioSettingsBackup.Configuration,
        currentSettings: TrioSettings,
        currentPreferences: Preferences
    ) -> TrioSettingsBackup.Configuration {
        var result = source
        result.settings.dosingMode = .open
        result.settings.cgm = currentSettings.cgm
        result.settings.cgmPluginIdentifier = currentSettings.cgmPluginIdentifier
        result.settings.isUploadEnabled = currentSettings.isUploadEnabled
        result.settings.isDownloadEnabled = currentSettings.isDownloadEnabled
        result.settings.useLocalGlucoseSource = currentSettings.useLocalGlucoseSource
        result.preferences.bolusIncrement = currentPreferences.bolusIncrement
        return result
    }

    static func onboardingConfiguration(_ source: TrioSettingsBackup.Configuration) throws -> TrioSettingsBackup.Configuration {
        var result = try TrioSettingsBackup.normalized(source)
        result.settings.dosingMode = .open
        return result
    }


}
