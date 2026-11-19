import Foundation
import Testing
@testable import Trio

@Suite("Legacy Therapy Settings Importer Tests", .serialized) struct LegacyTherapySettingsImporterTests {
    private let sport = TherapyProfileFixtures.profile("Sport", basal: [(0, 0.5)], sens: [(0, 70)], target: [(0, 120, 120)])
    private let importDate = Date(timeIntervalSince1970: 1_800_000_500)

    /// Settings files as earlier versions wrote them.
    private enum LegacyFiles {
        static let basal = """
        [
          {"start": "00:00:00", "minutes": 0, "rate": 0.85},
          {"start": "06:00:00", "minutes": 360, "rate": 1.05},
          {"start": "22:30:00", "minutes": 1350, "rate": 0.7}
        ]
        """
        static let carbRatios = """
        {"units": "grams", "schedule": [
          {"start": "00:00:00", "offset": 0, "ratio": 7.5},
          {"start": "11:00:00", "offset": 660, "ratio": 12}
        ]}
        """
        static let sensitivities = """
        {"units": "mg/dL", "user_preferred_units": "mg/dL", "sensitivities": [
          {"sensitivity": 42.5, "offset": 0, "start": "00:00:00"},
          {"sensitivity": 55, "offset": 480, "start": "08:00:00"}
        ]}
        """
        static let targets = """
        {"units": "mg/dL", "user_preferred_units": "mg/dL", "targets": [
          {"low": 100, "high": 100, "start": "00:00:00", "offset": 0},
          {"low": 110, "high": 110, "start": "21:00:00", "offset": 1260}
        ]}
        """
        static let sensitivitiesMmol = """
        {"units": "mmol/L", "user_preferred_units": "mmol/L", "sensitivities": [
          {"sensitivity": 2.5, "offset": 0, "start": "00:00:00"},
          {"sensitivity": 3, "offset": 480, "start": "08:00:00"}
        ]}
        """
        static let targetsMmol = """
        {"units": "mmol/L", "user_preferred_units": "mmol/L", "targets": [
          {"low": 5.5, "high": 5.5, "start": "00:00:00", "offset": 0},
          {"low": 6, "high": 6, "start": "21:00:00", "offset": 1260}
        ]}
        """
    }

    private func write(
        _ fileStorage: InMemoryFileStorage,
        basal: String? = LegacyFiles.basal,
        carbRatios: String? = LegacyFiles.carbRatios,
        sensitivities: String? = LegacyFiles.sensitivities,
        targets: String? = LegacyFiles.targets
    ) {
        if let basal { fileStorage.save(basal, as: OpenAPS.Settings.basalProfile) }
        if let carbRatios { fileStorage.save(carbRatios, as: OpenAPS.Settings.carbRatios) }
        if let sensitivities { fileStorage.save(sensitivities, as: OpenAPS.Settings.insulinSensitivities) }
        if let targets { fileStorage.save(targets, as: OpenAPS.Settings.bgTargets) }
    }

    /// Writes the files a version before this one kept for `profile`.
    private func write(_ fileStorage: InMemoryFileStorage, _ profile: TrioTherapyProfile) {
        fileStorage.save(profile.basalProfileEntries, as: OpenAPS.Settings.basalProfile)
        fileStorage.save(profile.carbRatios, as: OpenAPS.Settings.carbRatios)
        fileStorage.save(profile.insulinSensitivities, as: OpenAPS.Settings.insulinSensitivities)
        fileStorage.save(profile.bgTargets, as: OpenAPS.Settings.bgTargets)
    }

    private func importer(_ context: TherapyProfileTestContext) -> LegacyTherapySettingsImporter {
        let importDate = importDate
        return LegacyTherapySettingsImporter(
            fileStorage: context.fileStorage,
            profileStorage: context.profileStorage,
            now: { importDate }
        )
    }

    /// The therapy settings files and their migrated copies; other services keep their own files in the same storage.
    private func therapyFiles(_ context: TherapyProfileTestContext) -> [String: Data] {
        let names = Set(LegacyTherapySettingsImporter.files).union(migratedFiles)
        return context.fileStorage.files.filter { names.contains($0.key) }
    }

    private func remainingFiles(_ context: TherapyProfileTestContext) -> Set<String> {
        Set(therapyFiles(context).keys)
    }

    private let migratedFiles = Set(LegacyTherapySettingsImporter.files.map(LegacyTherapySettingsImporter.migratedName))

    @Test("Migrated files keep their name with a migrated suffix") func migratedNames() {
        #expect(
            LegacyTherapySettingsImporter
                .migratedName("settings/basal_profile.json") == "settings/basal_profile.migrated.json"
        )
        #expect(Set(LegacyTherapySettingsImporter.files) == [
            "settings/basal_profile.json",
            "settings/carb_ratios.json",
            "settings/insulin_sensitivities.json",
            "settings/bg_targets.json"
        ])
    }

    @Test("Settings files become the Default profile's values and are moved aside") func importsFiles() async throws {
        let context = try await TherapyProfileTestContext.make(live: nil)
        write(context.fileStorage)

        #expect(try await importer(context).importIfNeeded())

        let stored = try await context.profileStorage.fetchProfiles()
        #expect(stored.activeProfileName == "Default")
        #expect(stored.inactiveProfiles.isEmpty)
        let live = try context.profileStorage.requireLiveSettings()
        #expect(live.basal.map(\.seconds) == [0, 21600, 81000])
        #expect(live.basal.map(\.value) == [0.85, 1.05, 0.7].map(TherapyProfileFixtures.decimal))
        #expect(live.carbRatio.map(\.value) == [TherapyProfileFixtures.decimal(7.5), 12])
        #expect(live.sensitivity.map(\.value) == [TherapyProfileFixtures.decimal(42.5), 55])
        #expect(live.target.map(\.low) == [100, 110])
        #expect(remainingFiles(context) == migratedFiles)
        #expect(try await context.profileStorage.profileSwitchesNotYetUploaded().isEmpty)
        #expect(try context.relaunched().profileStorage.requireLiveSettings() == live)

        // The next launch finds nothing to import and leaves the stored values alone.
        #expect(try await !importer(context).importIfNeeded())
        #expect(try await context.profileStorage.fetchProfiles() == stored)
    }

    @Test("oref gets the same schedules from Core Data as it got from the settings files") func sameOrefInputs() async throws {
        let context = try await TherapyProfileTestContext.make(live: nil)
        write(context.fileStorage)
        let basalBefore = try JSONBridge.basalProfile(from: LegacyFiles.basal)
        let carbRatiosBefore = try JSONBridge.carbRatios(from: LegacyFiles.carbRatios)
        let sensitivitiesBefore = try JSONBridge.insulinSensitivities(from: LegacyFiles.sensitivities)
        let targetsBefore = try JSONBridge.bgTargets(from: LegacyFiles.targets)

        try await importer(context).importIfNeeded()
        // As oref reads them after a launch.
        let after = try context.relaunched().profileStorage.requireLiveSettings()

        #expect(after.basalProfileEntries == basalBefore)
        #expect(after.carbRatios.units == carbRatiosBefore.units)
        #expect(after.carbRatios.schedule.map(\.start) == carbRatiosBefore.schedule.map(\.start))
        #expect(after.carbRatios.schedule.map(\.offset) == carbRatiosBefore.schedule.map(\.offset))
        #expect(after.carbRatios.schedule.map(\.ratio) == carbRatiosBefore.schedule.map(\.ratio))
        #expect(after.insulinSensitivities.units == sensitivitiesBefore.units)
        #expect(after.insulinSensitivities.userPreferredUnits == sensitivitiesBefore.userPreferredUnits)
        #expect(after.insulinSensitivities.sensitivities.map(\.start) == sensitivitiesBefore.sensitivities.map(\.start))
        #expect(after.insulinSensitivities.sensitivities.map(\.offset) == sensitivitiesBefore.sensitivities.map(\.offset))
        #expect(
            after.insulinSensitivities.sensitivities.map(\.sensitivity) == sensitivitiesBefore.sensitivities.map(\.sensitivity)
        )
        #expect(after.bgTargets.units == targetsBefore.units)
        #expect(after.bgTargets.userPreferredUnits == targetsBefore.userPreferredUnits)
        #expect(after.bgTargets.targets.map(\.start) == targetsBefore.targets.map(\.start))
        #expect(after.bgTargets.targets.map(\.offset) == targetsBefore.targets.map(\.offset))
        #expect(after.bgTargets.targets.map(\.low) == targetsBefore.targets.map(\.low))
        #expect(after.bgTargets.targets.map(\.high) == targetsBefore.targets.map(\.high))
    }

    @Test("Basal rates are kept at three decimal places and a target's high value is its low value") func normalizes() async throws {
        let context = try await TherapyProfileTestContext.make(live: nil)
        write(
            context.fileStorage,
            basal: #"[{"start": "00:00:00", "minutes": 0, "rate": 0.07000000000000001}]"#,
            targets: """
            {"units": "mg/dL", "user_preferred_units": "mg/dL", "targets": [
              {"low": 100, "high": 120, "start": "00:00:00", "offset": 0}
            ]}
            """
        )

        try await importer(context).importIfNeeded()

        let live = try context.profileStorage.requireLiveSettings()
        #expect(live.basal.map(\.value) == [TherapyProfileFixtures.decimal(0.07)])
        #expect(live.target.map(\.low) == [100])
        #expect(live.target.map(\.high) == [100])
    }

    @Test("Insulin sensitivities and glucose targets in mmol/L are stored in mg/dL") func importsMmol() async throws {
        let context = try await TherapyProfileTestContext.make(live: nil)
        write(context.fileStorage, sensitivities: LegacyFiles.sensitivitiesMmol, targets: LegacyFiles.targetsMmol)

        try await importer(context).importIfNeeded()

        let live = try context.profileStorage.requireLiveSettings()
        func mgdL(_ value: Double) -> Decimal {
            context.fileStorage.parseSettingIfMmolL(value: TherapyProfileFixtures.decimal(value))
        }
        #expect(live.sensitivity.map(\.value) == [mgdL(2.5), mgdL(3)])
        #expect(live.target.map(\.low) == [mgdL(5.5), mgdL(6)])
        #expect(live.sensitivity.allSatisfy { $0.value >= 39 })
        #expect(live.target.allSatisfy { $0.low >= 39 })
        #expect(live.insulinSensitivities.units == .mgdL)
        #expect(live.bgTargets.units == .mgdL)
        #expect(live.basal.map(\.value) == [0.85, 1.05, 0.7].map(TherapyProfileFixtures.decimal))
        #expect(remainingFiles(context) == migratedFiles)
    }

    @Test("Without settings files nothing is stored and the bundled defaults stay in use") func noFiles() async throws {
        let context = try await TherapyProfileTestContext.make(live: nil)

        #expect(try await !importer(context).importIfNeeded())

        #expect(try await context.profileStorage.fetchProfiles() == .empty)
        #expect(try context.profileStorage.requireLiveSettings() == TrioTherapyProfile.bundledDefaults)
        #expect(remainingFiles(context).isEmpty)
    }

    @Test("Files that differ from the values stored with the active profile replace them") func filesReplaceStoredValues() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        let edited = TherapyProfileFixtures.profile("Default", carbratio: [(0, 7)])
        write(context.fileStorage, edited)

        try await importer(context).importIfNeeded()

        let relaunched = try context.relaunched()
        #expect(relaunched.manager.activeProfileName == "Default")
        #expect(relaunched.liveSettings == edited)
        #expect(relaunched.manager.profile(named: "Sport") == sport)
        #expect(try await relaunched.profileStorage.profileSwitchesNotYetUploaded().isEmpty)
    }

    @Test("A switch that wrote the files and stopped before storing the profiles is completed") func interruptedSwitch() async throws {
        let context = try await TherapyProfileTestContext.make()
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        try await context.manager.saveScheduledSwitches(
            [ScheduledProfileSwitch(profileName: "Sport", weekday: 2, time: 21600)],
            baseFingerprint: nil
        )
        let defaultValues = context.manager.activeProfile()
        write(context.fileStorage, sport)

        try await importer(context).importIfNeeded()

        let stored = try await context.profileStorage.fetchProfiles()
        #expect(stored.activeProfileName == "Sport")
        #expect(stored.activeProfileValues == sport)
        #expect(stored.inactiveProfiles == [defaultValues])
        #expect(stored.scheduledSwitches.map(\.profileName) == ["Sport"])
        #expect(stored.scheduledSwitchesSettledAt == importDate)
        #expect(try await context.profileStorage.profileSwitchesNotYetUploaded() == [
            TherapyProfileSwitch(name: "Sport", date: importDate)
        ])
        let relaunched = try context.relaunched()
        #expect(relaunched.manager.activeProfileName == "Sport")
        #expect(relaunched.liveSettings == sport)
        #expect(remainingFiles(context) == migratedFiles)
    }

    @Test("A failed save leaves the files and the stored profiles as they were") func failedSave() async throws {
        let context = try await TherapyProfileTestContext.make()
        let before = try await context.profileStorage.fetchProfiles()
        write(context.fileStorage)
        let files = therapyFiles(context)
        context.profileStorage.failsToStore = true

        await #expect(throws: TherapyProfileError.storageFailed) { try await importer(context).importIfNeeded() }

        #expect(therapyFiles(context) == files)
        #expect(try await context.profileStorage.fetchProfiles() == before)

        // The next launch imports them.
        context.profileStorage.failsToStore = false
        #expect(try await importer(context).importIfNeeded())
        #expect(context.liveSettings.carbRatio.map(\.value) == [TherapyProfileFixtures.decimal(7.5), 12])
        #expect(remainingFiles(context) == migratedFiles)
    }

    @Test("A file that cannot be read stops the import instead of taking the defaults") func unreadableFile() async throws {
        let context = try await TherapyProfileTestContext.make(live: nil)
        write(context.fileStorage, carbRatios: "{")
        let files = therapyFiles(context)

        await #expect(throws: LegacyTherapySettingsImportError.unreadableFile(OpenAPS.Settings.carbRatios)) {
            try await importer(context).importIfNeeded()
        }

        #expect(therapyFiles(context) == files)
        #expect(try await context.profileStorage.fetchProfiles() == .empty)
    }

    @Test("A schedule offset outside the day stops the import") func invalidOffset() async throws {
        let context = try await TherapyProfileTestContext.make(live: nil)
        write(context.fileStorage, basal: #"[{"start": "24:00:00", "minutes": 1440, "rate": 1}]"#)
        let files = therapyFiles(context)

        await #expect(throws: TherapyProfileStorageError.self) { try await importer(context).importIfNeeded() }

        #expect(therapyFiles(context) == files)
        #expect(try await context.profileStorage.fetchProfiles() == .empty)
    }

    @Test("Files left over after an import stopped while moving them keep the stored values of the moved ones") func partlyMoved(
    ) async throws {
        let context = try await TherapyProfileTestContext.make(live: nil)
        write(context.fileStorage)
        try await importer(context).importIfNeeded()
        let imported = try await context.profileStorage.fetchProfiles()

        // As when the app stopped after moving two of the four files.
        write(context.fileStorage, basal: nil, carbRatios: nil)

        #expect(try await importer(context).importIfNeeded())
        #expect(try await context.profileStorage.fetchProfiles() == imported)
        #expect(remainingFiles(context) == migratedFiles)
    }

    @Test("Without a file for a setting on a fresh store, that setting takes the bundled default") func missingFile() async throws {
        let context = try await TherapyProfileTestContext.make(live: nil)
        write(context.fileStorage, carbRatios: nil)

        try await importer(context).importIfNeeded()

        let live = try context.profileStorage.requireLiveSettings()
        #expect(live.carbRatio == TrioTherapyProfile.bundledDefaults.carbRatio)
        #expect(live.basal.map(\.value) == [0.85, 1.05, 0.7].map(TherapyProfileFixtures.decimal))
    }

    @Test("Files written again by an earlier version are imported again") func importedAgain() async throws {
        let context = try await TherapyProfileTestContext.make(live: nil)
        write(context.fileStorage)
        try await importer(context).importIfNeeded()

        let edited = TherapyProfileFixtures.profile("Default", carbratio: [(0, 9)])
        write(context.fileStorage, edited)
        #expect(try await importer(context).importIfNeeded())

        #expect(try context.relaunched().liveSettings == edited)
        #expect(remainingFiles(context) == migratedFiles)
        #expect(
            context.fileStorage.retrieve(
                LegacyTherapySettingsImporter.migratedName(OpenAPS.Settings.carbRatios),
                as: CarbRatios.self
            )?.schedule.map(\.ratio) == [9]
        )
    }
}
