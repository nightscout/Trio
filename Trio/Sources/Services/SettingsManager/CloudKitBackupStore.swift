import CloudKit
import Foundation

/// Read legacy records without decoding or reinstating service credentials.
private struct LegacyCloudSettingsEnvelope: Decodable {
    let settings: TrioSettingsBackup
}

struct TrioCloudBackupEntry: Identifiable {
    let id: String
    let createdAt: Date
    let origin: TrioSettingsBackup.Origin
    var name: String?
    let fingerprint: String
    var appVersion: String? = nil
    var schemaVersion: Int? = nil
    var validationMessage: String? = nil
}

/// Private CloudKit storage with encrypted payload, fingerprint, and name fields.
protocol TrioCloudBackupStoring {
    func upload(_ snapshot: TrioSettingsBackup) async throws -> TrioCloudBackupEntry
    func list() async throws -> [TrioCloudBackupEntry]
    func download(id: String) async throws -> TrioSettingsBackup
    func delete(id: String) async throws
    func rename(id: String, name: String) async throws -> TrioCloudBackupEntry
}

final class TrioCloudBackupStore: TrioCloudBackupStoring {
    private static let recordType = "TrioSettingsBackup"
    private let container: CKContainer

    init(container: CKContainer = .default()) {
        self.container = container
    }

    private var database: CKDatabase { container.privateCloudDatabase }

    func checkAvailability() async throws {
        let status = try await container.accountStatus()
        guard status == .available else { throw BackupError.iCloudUnavailable }
    }

    func upload(_ snapshot: TrioSettingsBackup) async throws -> TrioCloudBackupEntry {
        try await checkAvailability()
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: snapshot.id.uuidString))
        do { return try entry(from: await save(snapshot, to: record)) }
        catch let error as CKError where error.code == .serverRecordChanged {
            // Retries reuse the UUID and preserve any server-side rename.
            let existing = try await database.record(for: record.recordID)
            let saved = try Self.snapshot(from: existing)
            guard try saved.matchesUploadedSnapshot(snapshot.validated()) else { throw BackupError.integrityCheckFailed }
            return try entry(from: existing)
        }
    }

    func rename(id: String, name: String) async throws -> TrioCloudBackupEntry {
        try await checkAvailability()
        guard let name = TrioSettingsBackup.normalizedName(name) else { throw BackupError.backupNameRequired }
        let record = try await database.record(for: CKRecord.ID(recordName: id))
        var snapshot = try Self.snapshot(from: record)
        guard snapshot.origin == .manual else { throw BackupError.invalidCloudRecord }
        snapshot.name = name
        return try entry(from: await save(snapshot, to: record))
    }

    /// The record's change tag prevents overwriting concurrent renames.
    private func save(_ snapshot: TrioSettingsBackup, to record: CKRecord) async throws -> CKRecord {
        let snapshot = try snapshot.validated()
        record["createdAt"] = snapshot.createdAt as NSDate
        record["origin"] = snapshot.origin.rawValue as NSString
        record["appVersion"] = snapshot.appVersion as NSString
        record["schemaVersion"] = snapshot.schemaVersion as NSNumber
        record.encryptedValues["fingerprint"] = snapshot.fingerprint as NSString
        record.encryptedValues["name"] = snapshot.name as NSString?
        let bytes = try JSONEncoder().encode(snapshot)
        guard bytes.count <= TrioSettingsBackup.maximumSize else { throw BackupError.backupTooLarge }
        // CKAsset fields are unencrypted; reject oversized payloads instead of falling back to assets.
        guard bytes.count <= 750_000 else { throw BackupError.backupTooLarge }
        record["snapshotAsset"] = nil
        record.encryptedValues["snapshot"] = bytes as NSData
        return try await database.save(record)
    }

    func list() async throws -> [TrioCloudBackupEntry] {
        try await checkAvailability()
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        let keys = ["createdAt", "origin", "fingerprint", "name", "appVersion", "schemaVersion"]
        var page = try await database.records(matching: query, desiredKeys: keys)
        var entries: [TrioCloudBackupEntry] = []
        while true {
            for (id, result) in page.matchResults {
                do {
                    entries.append(try entry(from: result.get()))
                } catch {
                    // Keep an unavailable/corrupt record visible instead of hiding history.
                    entries.append(TrioCloudBackupEntry(
                        id: id.recordName,
                        createdAt: .distantPast,
                        origin: .automatic,
                        name: "Unavailable Backup",
                        fingerprint: "",
                        validationMessage: error.localizedDescription
                    ))
                }
            }
            guard let cursor = page.queryCursor else { break }
            page = try await database.records(continuingMatchFrom: cursor, desiredKeys: keys)
        }
        return entries.sorted { $0.createdAt > $1.createdAt }
    }

    func download(id: String) async throws -> TrioSettingsBackup {
        try await checkAvailability()
        let record = try await database.record(for: CKRecord.ID(recordName: id))
        return try Self.snapshot(from: record)
    }

    static func snapshot(from record: CKRecord) throws -> TrioSettingsBackup {
        guard let fingerprint = record.encryptedValues["fingerprint"] as? String else { throw BackupError.invalidCloudRecord }
        let bytes: Data
        if let data = record.encryptedValues["snapshot"] as? Data { bytes = data }
        else if let asset = record["snapshotAsset"] as? CKAsset, let url = asset.fileURL {
            bytes = try TrioSettingsBackup.readBackupData(from: url)
        } else { throw BackupError.invalidCloudRecord }
        guard bytes.count <= TrioSettingsBackup.maximumSize else { throw BackupError.backupTooLarge }
        let snapshot: TrioSettingsBackup
        // Legacy envelopes contribute settings only; credentials are ignored.
        if let legacy = try? JSONDecoder().decode(LegacyCloudSettingsEnvelope.self, from: bytes) {
            guard legacy.settings.fingerprint == fingerprint else { throw BackupError.integrityCheckFailed }
            snapshot = try legacy.settings.validated()
        } else {
            snapshot = try TrioSettingsBackup.decode(bytes, expectedFingerprint: fingerprint)
        }
        guard snapshot.id.uuidString == record.recordID.recordName else { throw BackupError.invalidCloudRecord }
        return snapshot
    }

    func delete(id: String) async throws {
        try await checkAvailability()
        do { _ = try await database.deleteRecord(withID: CKRecord.ID(recordName: id)) }
        catch let error as CKError where error.code == .unknownItem { /* Already deleted by another device. */ }
    }

    private func entry(from record: CKRecord) throws -> TrioCloudBackupEntry {
        guard let date = record["createdAt"] as? Date,
              let originName = record["origin"] as? String,
              let origin = TrioSettingsBackup.Origin(rawValue: originName),
              let fingerprint = record.encryptedValues["fingerprint"] as? String
        else { throw BackupError.invalidCloudRecord }
        return TrioCloudBackupEntry(
            id: record.recordID.recordName,
            createdAt: date,
            origin: origin,
            name: record.encryptedValues["name"] as? String,
            fingerprint: fingerprint,
            appVersion: record["appVersion"] as? String,
            schemaVersion: (record["schemaVersion"] as? NSNumber)?.intValue
        )
    }
}

