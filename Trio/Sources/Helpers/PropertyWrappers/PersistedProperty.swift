import Foundation

/// Attention! Do not use this wrapper for mutating structure with `didSet` handler into property owner!
/// `didSet` will never called if structure mutate into itself (by "mutating functions").
@propertyWrapper struct Persisted<Value: Codable & Equatable> {
    var wrappedValue: Value {
        get { getValue() ?? initialValue }
        set { setValue(newValue) }
    }

    private func getValue() -> Value? {
        lock?.lock()
        defer { lock?.unlock() }
        return storage.getValue(Value.self, forKey: key)
    }

    private mutating func setValue(_ value: Value) {
        lock?.lock()
        defer { lock?.unlock() }
        storage.setValue(value, forKey: key)
    }

    private let key: String
    private let storage: KeyValueStorage
    private let lock: NSRecursiveLock?
    private let initialValue: Value
    var isInitialValue: Bool {
        if let value = getValue() {
            return value == initialValue
        }
        return true
    }

    init(
        wrappedValue: Value,
        key: String,
        storage: KeyValueStorage = UserDefaults.standard,
        lock: NSRecursiveLock? = nil
    ) {
        self.storage = storage
        self.key = key
        self.lock = lock
        initialValue = wrappedValue
        lock?.lock()
        defer { lock?.unlock() }
        if storage.getValue(Value.self, forKey: key) == nil {
            setValue(wrappedValue)
        }
    }
}

@propertyWrapper public struct PersistedProperty<Value> {
    let key: String
    let storageURL: URL

    public init(key: String) {
        self.key = key

        let documents: URL
        guard let localDocuments = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            preconditionFailure("Could not get a documents directory URL.")
        }
        documents = localDocuments
        storageURL = documents.appendingPathComponent(key + ".plist")
    }

    public var wrappedValue: Value? {
        get {
            guard FileManager.default.fileExists(atPath: storageURL.path) else { return nil }
            do {
                let data = try Data(contentsOf: storageURL)

                guard let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? Value
                else {
                    warning(.storage, "Persisted value '\(key)' has an unexpected type")
                    return nil
                }
                return value
            } catch {
                warning(.storage, "Reading persisted value '\(key)' failed", error: error)
                return nil
            }
        }
        set {
            guard let newValue = newValue else {
                guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
                do {
                    try FileManager.default.removeItem(at: storageURL)
                    debug(.storage, "Removed persisted value '\(key)'")
                } catch {
                    warning(.storage, "Removing persisted value '\(key)' failed", error: error)
                }
                return
            }

            do {
                let data = try PropertyListSerialization.data(fromPropertyList: newValue, format: .binary, options: 0)
                try data.write(to: storageURL, options: .atomic)

                // Ensure appropriate protection level
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.none],
                    ofItemAtPath: storageURL.path
                )

                debug(.storage, "Saved persisted value '\(key)'")
            } catch {
                warning(.storage, "Saving persisted value '\(key)' failed", error: error)
            }
        }
    }
}

import Foundation

enum FileProtectionFixer {
    /// Ensures only critical persisted flags have safe file protection set.
    static func fixFlagFileProtectionForPropertyPersistentFlags() {
        let flagFiles = [
            "onboardingCompleted.plist",
            "crashlyticsSharingEnabled.plist",
            "lastCleanupDate.plist",
            "hasSeenFatProteinOrderChange.plist",
            "telemetrySharingEnabled.plist",
            "telemetryLastSentAt.plist",
            "telemetryAnonymousLastSentAt.plist",
            "telemetryLastAttemptAt.plist",
            "telemetryLastSentSha.plist",
            "telemetryLastFailureReason.plist",
            "telemetryColdLaunchTimes.plist",
            "telemetryInstallId.plist",
            "telemetryAttestForbidden.plist",
            "telemetryDebugServerURL.plist"
        ]

        let fileManager = FileManager.default

        guard let documentsURL = try? fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            warning(.storage, "Documents directory unavailable, skipping file protection update")
            return
        }

        for fileName in flagFiles {
            let fileURL = documentsURL.appendingPathComponent(fileName)

            guard fileManager.fileExists(atPath: fileURL.path) else {
                continue // Skip if file doesn’t exist yet
            }

            do {
                try fileManager.setAttributes(
                    [.protectionKey: FileProtectionType.none],
                    ofItemAtPath: fileURL.path
                )
                debug(.storage, "Updated file protection for \(fileName)")
            } catch {
                warning(.storage, "Updating file protection for \(fileName) failed", error: error)
            }
        }
    }
}
