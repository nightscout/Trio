import Foundation

enum LegacyTherapySettingsImportError: Error, LocalizedError, Equatable {
    case unreadableFile(String)
    case notStoredAsRead
    case fileNotRemoved(String)

    var errorDescription: String? {
        switch self {
        case let .unreadableFile(name):
            return "The therapy settings file \(name) could not be read."
        case .notStoredAsRead:
            return "The therapy settings did not read back from the database as they were stored."
        case let .fileNotRemoved(name):
            return "The therapy settings file \(name) could not be moved aside after it was imported."
        }
    }
}

/// Earlier versions kept the basal rates, carb ratios, insulin sensitivities and glucose targets in use in settings files.
/// This takes them over as the active profile's values in Core Data, once, and moves the files aside.
struct LegacyTherapySettingsImporter {
    static let files = [
        OpenAPS.Settings.basalProfile,
        OpenAPS.Settings.carbRatios,
        OpenAPS.Settings.insulinSensitivities,
        OpenAPS.Settings.bgTargets
    ]

    let fileStorage: FileStorage
    let profileStorage: TherapyProfileStorage
    var now: () -> Date = { Date() }

    /// `settings/basal_profile.json` becomes `settings/basal_profile.migrated.json`.
    static func migratedName(_ name: String) -> String {
        name.hasSuffix(".json") ? String(name.dropLast(".json".count)) + ".migrated.json" : name + ".migrated"
    }

    /// Returns true when settings files were there and are imported. The files are moved aside only after their values
    /// read back from Core Data; a throw leaves the files that were not moved yet in place, so the next launch tries again.
    @discardableResult func importIfNeeded() async throws -> Bool {
        let present = Self.files.filter { fileStorage.retrieveRaw($0) != nil }
        guard !present.isEmpty else {
            debug(.storage, "No legacy therapy settings to import")
            return false
        }

        let stored = try await profileStorage.fetchProfiles()
        let live = try legacySettings(present: Set(present), fallback: stored.liveSettings)

        var imported = stored
        var activeName = stored.activeProfileName ?? TrioTherapyProfile.defaultName
        var switchDate: Date?
        // When the files differ from the values stored with the active profile and equal another stored profile's, a
        // switch wrote the files and stopped before storing the profiles: that profile is active, and the stored values
        // belong to the previously active one.
        if let storedValues = stored.activeProfileValues, !storedValues.hasSameValues(as: live),
           let index = imported.inactiveProfiles.firstIndex(where: { $0.hasSameValues(as: live) })
        {
            let switchedTo = imported.inactiveProfiles.remove(at: index)
            imported.inactiveProfiles.append(storedValues.renamed(activeName))
            activeName = switchedTo.name
            switchDate = now()
            imported.scheduledSwitchesSettledAt = switchDate
            warning(.storage, "A therapy profile switch was interrupted and is completed with the import")
        }
        imported.activeProfileName = activeName
        imported.activeProfileValues = live.renamed(activeName)

        if imported != stored {
            try await profileStorage.storeProfiles(imported, switchDate: switchDate, switchTrigger: nil)
        }
        let readBack = try await profileStorage.fetchProfiles()
        guard readBack.activeProfileName == activeName, readBack.activeProfileValues?.hasSameValues(as: live) == true else {
            throw LegacyTherapySettingsImportError.notStoredAsRead
        }

        for name in present {
            let migratedName = Self.migratedName(name)
            if fileStorage.retrieveRaw(migratedName) != nil {
                fileStorage.remove(migratedName)
            }
            fileStorage.rename(name, to: migratedName)
            // A file left in place would replace later edits on the next launch.
            if fileStorage.retrieveRaw(name) != nil {
                fileStorage.remove(name)
            }
            guard fileStorage.retrieveRaw(name) == nil else {
                throw LegacyTherapySettingsImportError.fileNotRemoved(name)
            }
        }
        info(.storage, "Imported legacy therapy settings from \(present.count) files")
        return true
    }

    /// The settings as the files hold them, glucose values in mg/dL. A file that is not there takes `fallback`'s values.
    private func legacySettings(present: Set<String>, fallback: TrioTherapyProfile) throws -> TrioTherapyProfile {
        func read<Value: JSON>(_ name: String, as type: Value.Type) throws -> Value? {
            guard present.contains(name) else { return nil }
            guard let value = fileStorage.retrieve(name, as: type) else {
                throw LegacyTherapySettingsImportError.unreadableFile(name)
            }
            return value
        }

        var sensitivities = try read(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
        if let read = sensitivities, read.units == .mmolL || read.userPreferredUnits == .mmolL {
            info(.storage, "Converting legacy insulin sensitivities from mmol/L to mg/dL")
            sensitivities = InsulinSensitivities(
                units: .mgdL,
                userPreferredUnits: .mgdL,
                sensitivities: read.sensitivities.map {
                    InsulinSensitivityEntry(
                        sensitivity: fileStorage.parseSettingIfMmolL(value: $0.sensitivity),
                        offset: $0.offset,
                        start: $0.start
                    )
                }
            )
        }

        var targets = try read(OpenAPS.Settings.bgTargets, as: BGTargets.self)
        if let read = targets, read.units == .mmolL || read.userPreferredUnits == .mmolL {
            info(.storage, "Converting legacy glucose targets from mmol/L to mg/dL")
            targets = BGTargets(
                units: .mgdL,
                userPreferredUnits: .mgdL,
                targets: read.targets.map {
                    BGTargetEntry(
                        low: fileStorage.parseSettingIfMmolL(value: $0.low),
                        high: fileStorage.parseSettingIfMmolL(value: $0.high),
                        start: $0.start,
                        offset: $0.offset
                    )
                }
            )
        }

        return fallback.replacing(
            basalProfile: try read(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self),
            carbRatios: try read(OpenAPS.Settings.carbRatios, as: CarbRatios.self),
            insulinSensitivities: sensitivities,
            bgTargets: targets
        )
    }
}
