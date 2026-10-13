import CoreData
import CryptoKit
import Foundation

extension TrioCloudSettingsRestore {
    enum Phase: Equatable {
        case journalWritten
        case fileWritten(String)
        case presetsWritten
        case historyWritten
        case configurationWritten
        case verified
    }

    @MainActor static func performTransaction(
        newFiles: [(String, Data)], presets: TrioSettingsBackup.Presets,
        directory: URL, context: NSManagedObjectContext? = nil,
        defaults: UserDefaults = .standard,
        tddHistory: [TrioSettingsBackup.TDDRecord] = [],
        requiresPumpReconciliation: Bool = false,
        preflight: () throws -> Void = {},
        prepareHardware: () async throws -> Void = {},
        synchronizeCache: () throws -> Void = {},
        verifyConfiguration: () throws -> Void = {},
        verifyHardware: () async throws -> Void = {},
        phase: (Phase) throws -> Void = { _ in }
    ) async throws {
        let journalURL = directory.appendingPathComponent(journalFileName)
        guard !FileManager.default.fileExists(atPath: journalURL.path),
              newFiles.count == names.count, Set(newFiles.map(\.0)) == Set(names)
        else {
            throw BackupError.restoreFailed
        }
        let previousFiles = try names.map { name in
            let url = directory.appendingPathComponent(name)
            return PreviousFile(
                name: name,
                contents: FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
            )
        }
        let taskContext = context ?? CoreDataStack.shared.newTaskContext()
        let originalPresets = try await TrioSettingsBackup.readPresets(context: taskContext)
        func checkPreflight() throws {
            try preflight()
            let active = try taskContext.performAndWait {
                let overrides = OverrideStored.fetchRequest()
                overrides.predicate = NSPredicate(format: "enabled == YES")
                let targets = TempTargetStored.fetchRequest()
                targets.predicate = NSPredicate(format: "enabled == YES")
                return try taskContext.count(for: overrides) > 0 || taskContext.count(for: targets) > 0
            }
            guard !active else { throw BackupError.activeAdjustments }
        }
        try checkPreflight()
        let history = try await missingTDDHistory(tddHistory, context: taskContext)
        let journal = try Journal(
            files: previousFiles,
            presets: originalPresets,
            defaults: readDefaults(defaults: defaults),
            insertedTDDIDs: history.isEmpty ? nil : history.map(\.id),
            requiresPumpReconciliation: requiresPumpReconciliation ? true : nil
        ).sealed()
        let encoded = try JSONEncoder().encode(journal)
        // A successful restore also leaves an independent recoverable local rollback.
        try encoded.write(
            to: directory.appendingPathComponent(rollbackFileName),
            options: [.atomic, .completeFileProtection]
        )
        try encoded.write(to: journalURL, options: [.atomic, .completeFileProtection])
        try phase(.journalWritten)
        if requiresPumpReconciliation { defaults.set(true, forKey: pumpRecoveryKey) }
        try await prepareHardware()
        try checkPreflight()
        for (name, data) in newFiles {
            try checkPreflight()
            let target = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: [.atomic, .completeFileProtection])
            try phase(.fileWritten(name))
        }
        try await replacePresets(with: presets, context: taskContext)
        try phase(.presetsWritten)
        if !history.isEmpty {
            try await insertTDDHistory(history, context: taskContext)
            try phase(.historyWritten)
        }
        try checkPreflight()
        try synchronizeCache()
        try phase(.configurationWritten)
        for (name, expected) in newFiles {
            guard (try? TrioSettingsBackup.contentsEqual(Data(contentsOf: directory.appendingPathComponent(name)), expected)) ==
                true else { throw BackupError.restoreFailed }
        }
        try await verifyPresets(presets, context: taskContext)
        try checkPreflight()
        try verifyConfiguration()
        try await verifyHardware()
        try phase(.verified)
        try FileManager.default.removeItem(at: journalURL)
        if requiresPumpReconciliation { defaults.removeObject(forKey: pumpRecoveryKey) }
    }

    /// Run after Core Data initializes and before settings or device services load.
    static func recoverInterruptedRestoreIfNeeded(
        directory: URL? = nil,
        context: NSManagedObjectContext? = nil,
        defaults: UserDefaults = .standard
    ) async throws {
        let documents = directory ?? Self.documents
        let journalURL = documents.appendingPathComponent(journalFileName)
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return }
        let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
        try journal.verify()
        // Fail closed for legacy journals requiring hardware reconciliation.
        guard journal.requiresPumpReconciliation != true else { throw BackupError.pumpNotReady }
        guard journal.files.count == names.count, Set(journal.files.map(\.name)) == Set(names) else {
            throw BackupError.restoreFailed
        }
        // Check the entire journal before writing any file.
        if let saved = journal.defaults, !Set(saved.keys).isSubset(of: Set(TrioSettingsBackup.AppConfiguration.keys)) {
            throw BackupError.restoreFailed
        }
        for item in journal.files {
            if item.name == OpenAPS.Trio.settings, let contents = item.contents {
                _ = try JSONCoding.decoder.decode(TrioSettings.self, from: contents)
            }
        }
        for data in journal.defaults?.values ?? [String: Data]().values {
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
            guard object?["value"] != nil else { throw BackupError.restoreFailed }
        }
        for item in journal.files {
            let target = documents.appendingPathComponent(item.name)
            if let contents = item.contents {
                let data: Data
                if item.name == OpenAPS.Trio.settings {
                    var settings = try JSONCoding.decoder.decode(TrioSettings.self, from: contents)
                    settings.dosingMode = .open
                    data = try JSONCoding.encoder.encode(settings)
                } else { data = contents }
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target, options: [.atomic, .completeFileProtection])
            } else if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
        }

        if let ids = journal.insertedTDDIDs {
            let historyContext = context ?? CoreDataStack.shared.newTaskContext()
            try await historyContext.perform {
                let request = NSFetchRequest<NSManagedObject>(entityName: "TDDStored")
                request.predicate = NSPredicate(format: "id IN %@", ids)
                for row in try historyContext.fetch(request) { historyContext.delete(row) }
                do { if historyContext.hasChanges { try historyContext.save() } }
                catch { historyContext.rollback()
                    throw error }
            }
        }
        try await replacePresets(with: journal.presets, context: context)
        if let saved = journal.defaults {
            for key in TrioSettingsBackup.AppConfiguration.keys {
                if let data = saved[key] {
                    let object = try PropertyListSerialization
                        .propertyList(from: data, options: [], format: nil) as? [String: Any]
                    guard let value = object?["value"] else { throw BackupError.restoreFailed }
                    defaults.set(value, forKey: key)
                } else { defaults.removeObject(forKey: key) }
            }
            guard try readDefaults(defaults: defaults) == saved else { throw BackupError.restoreFailed }
        }
        for item in journal.files {
            let target = documents.appendingPathComponent(item.name)
            if let old = item.contents {
                if item.name == OpenAPS.Trio.settings {
                    let recovered = try JSONCoding.decoder.decode(TrioSettings.self, from: Data(contentsOf: target))
                    var expected = try JSONCoding.decoder.decode(TrioSettings.self, from: old)
                    expected.dosingMode = .open
                    guard recovered == expected else { throw BackupError.restoreFailed }
                } else {
                    guard try Data(contentsOf: target) == old else { throw BackupError.restoreFailed }
                }
            } else if FileManager.default.fileExists(atPath: target.path) { throw BackupError.restoreFailed }
        }
        try await verifyPresets(journal.presets, context: context)
        try FileManager.default.removeItem(at: journalURL)
        if context == nil { await CoreDataStack.shared.fetchPersistentHistory() }
    }


}
