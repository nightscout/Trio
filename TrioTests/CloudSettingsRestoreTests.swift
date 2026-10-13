import CloudKit
import CoreData
import CryptoKit
import Foundation
import Testing
@testable import Trio

extension CloudSettingsBackupTests {
    private func context() async throws -> NSManagedObjectContext {
        let container = NSPersistentContainer(name: "BackupTest", managedObjectModel: CoreDataStack.managedObjectModel)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        return container.newBackgroundContext()
    }

    @Test("Preset insertion, editing, deletion and ordering preserve treatment history") func coreDataPresets() async throws {
        let context = try await context()
        try await context.perform {
            let history = OverrideStored(context: context)
            history.isPreset = false
            history.name = "Historical"
            history.percentage = 100
            let targetHistory = TempTargetStored(context: context)
            targetHistory.isPreset = false
            targetHistory.name = "Historical target"
            try context.save()
        }
        let preset = TrioSettingsBackup.OverridePreset(
            name: "Exercise",
            order: 2,
            percentage: 70,
            duration: 60,
            indefinite: false,
            target: 120,
            isf: true,
            cr: false,
            isfAndCr: false,
            advancedSettings: true,
            smbIsScheduledOff: false,
            smbIsOff: true,
            smbMinutes: 15,
            uamMinutes: 20,
            start: 0,
            end: 23
        )
        let presets = TrioSettingsBackup.Presets(
            overrides: [preset],
            tempTargets: [.init(name: "Activity", order: 1, duration: 60, target: 120, halfBasalTarget: 160)],
            meals: [.init(dish: "Lunch", carbs: 42, fat: 10, protein: 20)]
        )
        try await TrioCloudSettingsRestore.replacePresets(with: presets, context: context)
        let first = try await TrioSettingsBackup.readPresets(context: context)
        #expect(first.overrides.first?.order == 2)
        #expect(first.overrides.first?.smbMinutes == 15)
        #expect(first.tempTargets.first?.halfBasalTarget == 160)
        #expect(first.meals.first?.carbs == 42)
        try await context.perform {
            let request = OverrideStored.fetchRequest()
            request.predicate = NSPredicate(format: "isPreset == YES")
            let row = try #require(context.fetch(request).first)
            #expect(!row.enabled)
            #expect(row.overrideRun == nil)
            row.orderPosition = 3
            row.percentage = 80
            let targets = TempTargetStored.fetchRequest()
            targets.predicate = NSPredicate(format: "isPreset == YES")
            #expect(try context.fetch(targets).allSatisfy { !$0.enabled && $0.tempTargetRun == nil })
            try context.save()
        }
        let edited = try await TrioSettingsBackup.readPresets(context: context)
        #expect(edited.overrides.first?.order == 3)
        #expect(edited.overrides.first?.percentage == 80)
        try await context.perform {
            let overrideRequest = OverrideStored.fetchRequest()
            overrideRequest.predicate = NSPredicate(format: "isPreset == YES")
            let override = try #require(context.fetch(overrideRequest).first)
            let run = OverrideRunStored(context: context)
            run.id = UUID()
            run.name = "Historical preset run"
            run.override = override
            let targetRequest = TempTargetStored.fetchRequest()
            targetRequest.predicate = NSPredicate(format: "isPreset == YES")
            let target = try #require(context.fetch(targetRequest).first)
            let targetRun = TempTargetRunStored(context: context)
            targetRun.id = UUID()
            targetRun.name = "Historical target run"
            targetRun.tempTarget = target
            try context.save()
        }
        try await TrioCloudSettingsRestore.replacePresets(
            with: .init(overrides: [], tempTargets: [], meals: []),
            context: context
        )
        let empty = try await TrioSettingsBackup.readPresets(context: context)
        #expect(empty.overrides.isEmpty && empty.tempTargets.isEmpty && empty.meals.isEmpty)
        try await context.perform {
            let overrides = try context.fetch(OverrideStored.fetchRequest())
            let targets = try context.fetch(TempTargetStored.fetchRequest())
            #expect(overrides.contains(where: { $0.name == "Historical" }))
            #expect(targets.contains(where: { $0.name == "Historical target" }))
            let runs = try context.fetch(OverrideRunStored.fetchRequest())
            let targetRuns = try context.fetch(TempTargetRunStored.fetchRequest())
            #expect(runs.first?.override?.percentage == 80)
            #expect(runs.first?.override?.isPreset == false)
            #expect(targetRuns.first?.tempTarget?.target?.decimalValue == 120)
            #expect(targetRuns.first?.tempTarget?.isPreset == false)
        }
    }

    @Test("Onboarding preserves non-default preferences and forces Open Loop") func onboardingConfiguration() throws {
        var prefs = Preferences()
        prefs.maxIOB = 5
        prefs.sigmoid = true
        prefs.useWeightedAverage = true
        prefs.insulinPeakTime = 65
        prefs.enableSMBAlways = true
        var source = validConfiguration(preferences: prefs)
        source.settings.dosingMode = .closed
        let restored = try TrioCloudSettingsRestore.onboardingConfiguration(source)
        #expect(restored.settings.dosingMode == .open)
        #expect(restored.preferences.maxIOB == 5)
        #expect(restored.preferences.sigmoid && restored.preferences.useWeightedAverage)
        #expect(restored.preferences.insulinPeakTime == 65)
        #expect(restored.preferences.enableSMBAlways)
    }

    #if os(iOS)
        @MainActor
        @Test("Staged onboarding restoration cannot run manual default-saving code") func onboardingCompletionDoesNotSaveDefaults() throws {
            let state = Onboarding.StateModel()
            state.pendingCloudRestore = try makeBackup(validConfiguration())
            // No injected SettingsManager/FileStorage: an accidental save would fail.
            state.saveOnboardingData()
            #expect(state.pendingCloudRestore != nil)
            state.chooseCloudRestoreOption(.startFresh)
            #expect(state.pendingCloudRestore == nil)
        }
    #endif

    private enum Interrupted: Error { case terminated }

    @MainActor
    @Test(
        "Interruption at every persistence phase recovers all files and presets",
        arguments: Array(0 ..< 11)
    ) func interruptedRestore(_ stop: Int) async throws {
        let directory = try directory()
        let context = try await context()
        let originals = validConfiguration().presets
        try await TrioCloudSettingsRestore.replacePresets(with: originals, context: context)
        let defaults = isolatedDefaults()
        defaults.set("dark", forKey: "colorSchemePreference")
        // Original files are absent: recovery must remove partially-created files.
        let files = TrioCloudSettingsRestore.names.map { ($0, Data("{}".utf8)) }
        var phaseIndex = 0
        await #expect(throws: Interrupted.self) {
            try await TrioCloudSettingsRestore.performTransaction(
                newFiles: files,
                presets: .init(overrides: [], tempTargets: [], meals: []),
                directory: directory,
                context: context,
                defaults: defaults,
                synchronizeCache: { defaults.set("light", forKey: "colorSchemePreference") },
                phase: { _ in
                    defer { phaseIndex += 1 }
                    if phaseIndex == stop { throw Interrupted.terminated }
                }
            )
        }
        #expect(
            journalExists(in: directory)
        )
        try await TrioCloudSettingsRestore.recoverInterruptedRestoreIfNeeded(
            directory: directory,
            context: context,
            defaults: defaults
        )
        #expect(
            !journalExists(in: directory)
        )
        for name in TrioCloudSettingsRestore.names {
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path))
        }
        let recovered = try await TrioSettingsBackup.readPresets(context: context)
        #expect(recovered.meals.first?.dish == "Lunch")
        #expect(defaults.string(forKey: "colorSchemePreference") == "dark")
    }

    @MainActor
    @Test("Persistence verification failure retains journal for rollback") func failedVerification() async throws {
        let directory = try directory()
        let context = try await context()
        let files = TrioCloudSettingsRestore.names.map { ($0, Data("{}".utf8)) }
        await #expect(throws: BackupError.self) {
            try await TrioCloudSettingsRestore.performTransaction(
                newFiles: files,
                presets: validConfiguration().presets,
                directory: directory,
                context: context,
                defaults: isolatedDefaults(),
                synchronizeCache: {
                    try Data("unexpected mutation".utf8).write(to: directory.appendingPathComponent(files[0].0))
                }
            )
        }
        #expect(
            journalExists(in: directory)
        )
        try await TrioCloudSettingsRestore.recoverInterruptedRestoreIfNeeded(
            directory: directory,
            context: context,
            defaults: isolatedDefaults()
        )
    }

    @MainActor
    @Test("Active adjustments reject restore before any journal or file writes") func activeAdjustmentTransaction() async throws {
        let directory = try directory()
        let context = try await context()
        try await context.perform {
            let target = TempTargetStored(context: context)
            target.enabled = true
            target.isPreset = false
            try context.save()
        }
        await #expect(throws: BackupError.activeAdjustments) {
            try await TrioCloudSettingsRestore.performTransaction(
                newFiles: TrioCloudSettingsRestore.names.map { ($0, Data()) },
                presets: validConfiguration().presets, directory: directory, context: context, defaults: isolatedDefaults()
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @MainActor
    @Test("Successful persistence keeps a recoverable rollback and preserves non-default therapy") func successfulTransaction(
    ) async throws {
        let directory = try directory()
        let context = try await context()
        let original = validConfiguration()
        let originalSettings = directory.appendingPathComponent(OpenAPS.Trio.settings)
        try FileManager.default.createDirectory(
            at: originalSettings.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var settings = original.settings
        settings.dosingMode = .closed
        try JSONCoding.encoder.encode(settings).write(to: originalSettings)
        let preferencesURL = directory.appendingPathComponent(OpenAPS.Settings.preferences)
        try JSONCoding.encoder.encode(original.preferences).write(to: preferencesURL)
        try await TrioCloudSettingsRestore.replacePresets(with: original.presets, context: context)
        var preferences = Preferences()
        preferences.maxIOB = 5
        preferences.sigmoid = true
        preferences.insulinPeakTime = 65
        let candidate = try TrioCloudSettingsRestore.onboardingConfiguration(validConfiguration(preferences: preferences))
        let files = try TrioCloudSettingsRestore.configurationFiles(candidate)
        var verified = false
        let defaults = isolatedDefaults()
        try await TrioCloudSettingsRestore.performTransaction(
            newFiles: files,
            presets: candidate.presets,
            directory: directory,
            context: context,
            defaults: defaults,
            verifyConfiguration: { verified = true }
        )
        #expect(verified)
        #expect(
            !journalExists(in: directory)
        )
        let saved = try JSONCoding.decoder.decode(Preferences.self, from: Data(contentsOf: preferencesURL))
        #expect(saved.maxIOB == 5 && saved.sigmoid && saved.insulinPeakTime == 65)
        let rollback = directory.appendingPathComponent(TrioCloudSettingsRestore.rollbackFileName)
        #expect(FileManager.default.fileExists(atPath: rollback.path))
        try FileManager.default.copyItem(
            at: rollback,
            to: directory.appendingPathComponent(TrioCloudSettingsRestore.journalFileName)
        )
        try await TrioCloudSettingsRestore.recoverInterruptedRestoreIfNeeded(
            directory: directory,
            context: context,
            defaults: defaults
        )
        let recovered = try JSONCoding.decoder.decode(Preferences.self, from: Data(contentsOf: preferencesURL))
        #expect(recovered == original.preferences)
        let recoveredSettings = try JSONCoding.decoder.decode(TrioSettings.self, from: Data(contentsOf: originalSettings))
        #expect(recoveredSettings.dosingMode == .open)
    }

    @MainActor
    @Test("A real filesystem write failure retains a journal and can be rolled back") func filesystemFailure() async throws {
        let directory = try directory()
        let context = try await context()
        let blocked = directory.appendingPathComponent("settings")
        try Data("original blocker".utf8).write(to: blocked)
        let defaults = isolatedDefaults()
        await #expect(throws: Error.self) {
            try await TrioCloudSettingsRestore.performTransaction(
                newFiles: TrioCloudSettingsRestore.names.map { ($0, Data("{}".utf8)) },
                presets: validConfiguration().presets, directory: directory, context: context, defaults: defaults
            )
        }
        try await TrioCloudSettingsRestore.recoverInterruptedRestoreIfNeeded(
            directory: directory,
            context: context,
            defaults: defaults
        )
        #expect(try Data(contentsOf: blocked) == Data("original blocker".utf8))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(OpenAPS.Settings.preferences).path))
    }

    @MainActor
    @Test("Core Data save failure keeps rollback until persistence becomes available") func coreDataSaveFailure() async throws {
        let directory = try directory()
        let ordinary = try await context()
        // Persist a real prior configuration so rollback itself requires a save.
        try await TrioCloudSettingsRestore.replacePresets(with: validConfiguration().presets, context: ordinary)
        let context = CloudBackupFailingSaveContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = ordinary.persistentStoreCoordinator
        let defaults = isolatedDefaults()
        await #expect(throws: CloudBackupFailingSaveContext.Failure.self) {
            try await TrioCloudSettingsRestore.performTransaction(
                newFiles: TrioCloudSettingsRestore.names.map { ($0, Data("{}".utf8)) },
                presets: validConfiguration().presets, directory: directory, context: context, defaults: defaults
            )
        }
        await #expect(throws: CloudBackupFailingSaveContext.Failure.self) {
            try await TrioCloudSettingsRestore.recoverInterruptedRestoreIfNeeded(
                directory: directory,
                context: context,
                defaults: defaults
            )
        }
        let clean = await context.perform { !context.hasChanges && context.transactionAuthor == nil }
        #expect(clean)
        #expect(
            journalExists(in: directory)
        )
        await context.perform { context.shouldFail = false }
        try await TrioCloudSettingsRestore.recoverInterruptedRestoreIfNeeded(
            directory: directory,
            context: context,
            defaults: defaults
        )
        #expect(
            !journalExists(in: directory)
        )
    }

    @MainActor
    @Test("Reinstallation checks cloud history before uploading an identical automatic snapshot") func reinstallDeduplication(
    ) async throws {
        let directory = try directory()
        let cloud = CloudBackupFakeCloud()
        let snapshot = try makeBackup(validConfiguration(), origin: .automatic)
        cloud.history = [.init(
            id: snapshot.id.uuidString,
            createdAt: snapshot.createdAt,
            origin: .automatic,
            name: nil,
            fingerprint: snapshot.fingerprint
        )]
        cloud.downloads[snapshot.id.uuidString] = snapshot
        let coordinator = coordinator(
            cloud: cloud,
            directory: directory,
            capture: { _, _ in snapshot }
        )
        await coordinator.runAutomaticBackup()
        #expect(cloud.uploads.isEmpty)
        #expect(try coordinator.loadQueue().isEmpty)
        coordinator.automaticEnabled = false
    }

    @MainActor
    @Test("Retention treats origins separately, ignores unavailable records and retries failed cleanup") func retention() async throws {
        let directory = try directory()
        let cloud = CloudBackupFakeCloud()
        let now = Date()
        cloud.history = TrioSettingsBackup.Origin.allCases.flatMap { origin in
            (0 ..< 5).map { index in
                TrioCloudBackupEntry(
                    id: "\(origin.rawValue)-\(index)",
                    createdAt: now.addingTimeInterval(-Double(index)),
                    origin: origin,
                    fingerprint: "test"
                )
            }
        }
        cloud.history.append(.init(
            id: "unreadable",
            createdAt: .distantPast,
            origin: .manual,
            fingerprint: "",
            validationMessage: "Unavailable"
        ))
        let coordinator = coordinator(cloud: cloud, directory: directory)
        try await coordinator.setRetentionLimit(3, for: .manual)
        #expect(cloud.deleted == ["manual-3", "manual-4"])
        cloud.fail = true
        await #expect(throws: BackupError.iCloudUnavailable) { try await coordinator.setRetentionLimit(3, for: .automatic) }
        #expect(coordinator.retentionLimit(for: .automatic) == 3)
        cloud.fail = false
        await coordinator.runAutomaticBackup(capturePending: false)
        #expect(cloud.deleted == ["manual-3", "manual-4", "automatic-3", "automatic-4"])
        #expect(cloud.history.contains { $0.id == "unreadable" })
        coordinator.automaticEnabled = false
    }

    @MainActor
    @Test("Pending manual backups remain independent of the automatic toggle") func manualRetryWhenAutomaticDisabled() async throws {
        let directory = try directory()
        let cloud = CloudBackupFakeCloud()
        cloud.fail = true
        let coordinator = coordinator(cloud: cloud, directory: directory)
        await #expect(throws: BackupError.iCloudUnavailable) {
            _ = try await coordinator.createManualBackup(name: "Offline manual") }
        coordinator.automaticEnabled = false
        cloud.fail = false
        await coordinator.runAutomaticBackup(capturePending: false)
        #expect(cloud.uploads.count == 1)
        #expect(try coordinator.loadQueue().isEmpty)
    }

    @Test("Corrupt and incomplete rollback journals fail without touching configuration") func corruptJournal() async throws {
        let directory = try directory()
        let context = try await context()
        let marker = directory.appendingPathComponent("preferences.json")
        try Data("original".utf8).write(to: marker)
        let journal = TrioCloudSettingsRestore.Journal(
            files: [.init(name: "../unsafe", contents: Data())],
            presets: validConfiguration().presets
        )
        let journalURL = directory.appendingPathComponent(TrioCloudSettingsRestore.journalFileName)
        try JSONEncoder().encode(journal).write(to: journalURL)
        await #expect(throws: BackupError.self) {
            try await TrioCloudSettingsRestore.recoverInterruptedRestoreIfNeeded(
                directory: directory,
                context: context,
                defaults: isolatedDefaults()
            )
        }
        #expect(try Data(contentsOf: marker) == Data("original".utf8))
        #expect(FileManager.default.fileExists(atPath: journalURL.path))
    }

    func tdd(_ date: Date, id: UUID = UUID(), total: Decimal = 40) -> TrioSettingsBackup.TDDRecord {
        .init(id: id, date: date, total: total, bolus: 20, tempBasal: 10, scheduledBasal: 10, weightedAverage: 40)
    }

    func historyBackup(_ history: [TrioSettingsBackup.TDDRecord], createdAt: Date) throws -> TrioSettingsBackup {
        var backup = try makeBackup(validConfiguration(), createdAt: createdAt)
        backup.dynamicISFHistory = history
        backup.historyChecksum = try TrioSettingsBackup.historyDigest(history)
        return backup
    }

    @Test("History has independent integrity and does not change configuration deduplication") func historyIntegrity() throws {
        let now = Date()
        var backup = try historyBackup([tdd(now.addingTimeInterval(-300))], createdAt: now)
        let restored = try TrioSettingsBackup.decode(JSONEncoder().encode(backup))
        #expect(restored.dynamicISFHistory == backup.dynamicISFHistory)
        #expect(backup.fingerprint == (try makeBackup(validConfiguration())).fingerprint)
        backup.dynamicISFHistory = [tdd(now.addingTimeInterval(-300), total: 100)]
        #expect(throws: BackupError.integrityCheckFailed) { _ = try backup.validated() }
    }

    @Test("History uses each sample’s ten-day age, preserves dates and rejects future records") func historyAge() throws {
        let now = Date()
        let backup = try historyBackup([tdd(now.addingTimeInterval(-86400))], createdAt: now)
        #expect(backup.eligibleTDDHistory(now: now.addingTimeInterval(7 * 86400)).count == 1)
        #expect(backup.eligibleTDDHistory(now: now.addingTimeInterval(9 * 86400 - 1)).count == 1)
        #expect(backup.eligibleTDDHistory(now: now.addingTimeInterval(9 * 86400)).isEmpty)
        #expect(backup.eligibleTDDHistory(now: now.addingTimeInterval(-1)).isEmpty)
        #expect(backup.eligibleTDDHistory(now: now).first?.date == now.addingTimeInterval(-86400))
        let future = try historyBackup([tdd(now.addingTimeInterval(1))], createdAt: now)
        #expect(throws: BackupError.invalidTherapyConfiguration) { _ = try future.validated() }
    }

    @Test("Schema-three files remain readable without imported history") func schemaThree() throws {
        let current = try makeBackup(validConfiguration())
        let legacy = try makeBackup(current.configuration, schemaVersion: 3)
        let decoded = try TrioSettingsBackup.decode(JSONEncoder().encode(legacy))
        #expect(decoded.eligibleTDDHistory().isEmpty)
        #expect(decoded.fingerprint == current.fingerprint)
    }

    @Test("Configured restore preserves connections and pump bolus increment, forces Open Loop") func configuredConnections() throws {
        var settings = TrioSettings()
        settings.cgmPluginIdentifier = "existing-cgm"
        settings.isUploadEnabled = true
        settings.isDownloadEnabled = true
        settings.useLocalGlucoseSource = true
        var preferences = Preferences()
        preferences.bolusIncrement = 0.05
        let restored = TrioCloudSettingsRestore.configuredConfiguration(
            validConfiguration(),
            currentSettings: settings,
            currentPreferences: preferences
        )
        #expect(restored.settings.dosingMode == .open)
        #expect(restored.settings.cgmPluginIdentifier == "existing-cgm")
        #expect(
            restored.settings.isUploadEnabled && restored.settings.isDownloadEnabled && restored.settings
                .useLocalGlucoseSource
        )
        #expect(restored.preferences.bolusIncrement == 0.05)
    }

    @MainActor
    @Test("History import deduplicates five-minute slots and rollback removes only new summaries") func historyRollback() async throws {
        let directory = try directory()
        let context = try await context()
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 300) * 300)
        let existingID = UUID()
        try await context.perform {
            let row = NSEntityDescription.insertNewObject(forEntityName: "TDDStored", into: context)
            row.setValue(existingID, forKey: "id")
            row.setValue(now, forKey: "date")
            row.setValue(NSDecimalNumber(value: 50), forKey: "total")
            try context.save()
        }
        let next = tdd(now.addingTimeInterval(-300))
        let history = [tdd(now.addingTimeInterval(1)), next, tdd(now.addingTimeInterval(-299))]
        let missing = try await TrioCloudSettingsRestore.missingTDDHistory(history, context: context)
        #expect(missing.count == 1)
        let candidate = validConfiguration()
        await #expect(throws: BackupError.restoreFailed) {
            try await TrioCloudSettingsRestore.performTransaction(
                newFiles: TrioCloudSettingsRestore.configurationFiles(candidate),
                presets: candidate.presets,
                directory: directory,
                context: context,
                defaults: isolatedDefaults(),
                tddHistory: history,
                phase: { if $0 == .historyWritten { throw BackupError.restoreFailed } }
            )
        }
        let before = try await TrioSettingsBackup.readTDDHistory(context: context, now: now.addingTimeInterval(10))
        #expect(before.count == 2)
        try await TrioCloudSettingsRestore.recoverInterruptedRestoreIfNeeded(
            directory: directory,
            context: context,
            defaults: isolatedDefaults()
        )
        let after = try await TrioSettingsBackup.readTDDHistory(context: context, now: now.addingTimeInterval(10))
        #expect(after.count == 1 && after[0].id == existingID && after[0].total == 50)
        #expect(after[0].date == now)
    }

    @MainActor
    @Test("Gap-filled history uses the existing readiness check and preserves local samples") func historyReadiness() async throws {
        let context = try await context()
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 300) * 300 - 300)
        let existingID = UUID()
        let gap = tdd(now.addingTimeInterval(-1000 * 300))
        try await context.perform {
            for index in 0 ..< 1512 where index != 1000 {
                let row = NSEntityDescription.insertNewObject(forEntityName: "TDDStored", into: context)
                row.setValue(index == 0 ? existingID : UUID(), forKey: "id")
                row.setValue(now.addingTimeInterval(-Double(index) * 300), forKey: "date")
                row.setValue(NSDecimalNumber(value: 50), forKey: "total")
            }
            try context.save()
        }
        #expect(try await !BaseTDDStorage.hasSufficientTDD(context: context))
        let backup = try historyBackup([tdd(now.addingTimeInterval(1), total: 99), gap], createdAt: now.addingTimeInterval(10))
        let missing = try await TrioCloudSettingsRestore.missingTDDHistory(backup.eligibleTDDHistory(), context: context)
        #expect(missing == [gap])
        try await TrioCloudSettingsRestore.insertTDDHistory(missing, context: context)
        #expect(try await BaseTDDStorage.hasSufficientTDD(context: context))
        let restored = try await TrioSettingsBackup.readTDDHistory(context: context, now: now.addingTimeInterval(10))
        #expect(restored.count == 1512)
        #expect(restored.first { $0.id == existingID }?.total == 50)
        #expect(restored.first { $0.id == existingID }?.date == now)
        #expect(restored.first { $0.id == gap.id } == gap)
    }

    @MainActor
    @Test("Qualified local Dynamic ISF history is never supplemented by a backup") func preserveQualifiedHistory() async throws {
        let context = try await context()
        let now = Date()
        try await context.perform {
            for index in 0 ..< 1512 {
                let row = NSEntityDescription.insertNewObject(forEntityName: "TDDStored", into: context)
                row.setValue(UUID(), forKey: "id")
                row.setValue(now.addingTimeInterval(-Double(index) * 300), forKey: "date")
                row.setValue(NSDecimalNumber(value: 50), forKey: "total")
            }
            try context.save()
        }
        let missing = try await TrioCloudSettingsRestore.missingTDDHistory(
            [tdd(now.addingTimeInterval(-6 * 86400))],
            context: context
        )
        #expect(missing.isEmpty)
    }

    @Test(
        "Open Loop is persisted before restore even on a fresh installation without settings folders"
    ) func freshOpenLoopPersistence() throws {
        let directory = try directory()
        var source = TrioSettings()
        source.dosingMode = .closed
        let open = try TrioCloudSettingsRestore.persistOpenLoop(source, directory: directory)
        let persisted = try JSONCoding.decoder.decode(TrioSettings.self, from: Data(
            contentsOf:
            directory.appendingPathComponent(OpenAPS.Trio.settings)
        ))
        #expect(open.dosingMode == .open && persisted.dosingMode == .open)
    }
}
