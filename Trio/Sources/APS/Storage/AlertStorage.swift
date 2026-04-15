import Combine
import Foundation
import SwiftDate
import Swinject

protocol AlertObserver {
    func AlertDidUpdate(_ alerts: [AlertEntry])
}

protocol AlertHistoryStorage {
    func addAlert(_ alert: AlertEntry)
    func acknowledgeAlert(_ issuedAt: Date, _ error: String?)
    func removeAlert(identifier: String)
    func unacknowledgedAlertsWithinLast24Hours() -> [AlertEntry]
    func broadcastAlertUpdates()
    func syncDate() -> Date
    var unacknowledgedAlertsPublisher: PassthroughSubject<Bool, Never> { get }
}

final class BaseAlertHistoryStorage: AlertHistoryStorage, Injectable {
    private let processQueue = DispatchQueue.markedQueue(label: "BaseAlertsStorage.processQueue")

    private let defaults: UserDefaults

    /// Legacy JSON file storage used only for one-time migration from the historical on-disk JSON file.
    // FIXME: this can be removed in later releases
    @Injected() private var fileStorage: FileStorage!

    @Injected() private var broadcaster: Broadcaster!

    /// Emits `true` whenever there is at least one unacknowledged alert in the last 24 hours.
    let unacknowledgedAlertsPublisher = PassthroughSubject<Bool, Never>()

    private enum Keys {
        /// UserDefaults key holding the encoded `[AlertEntry]` payload.
        static let alertsData = "openaps.monitor.alertHistory.data"
        /// UserDefaults key used as a one-time migration flag.
        static let alertsMigrationDone = "openaps.monitor.alertHistory.migrated"
    }

    /// Creates a new alert history storage.
    ///
    /// On initialization this performs a one-time migration from the legacy JSON file
    /// (`OpenAPS.Monitor.alertHistory`, i.e.,`"monitor/alerthistory.json"`) into UserDefaults.
    /// After initialization, all reads/writes happen via UserDefaults only.
    ///
    /// - Parameters:
    ///   - resolver: Swinject resolver used for dependency injection.
    ///   - userDefaults: The UserDefaults instance used for persistence. Defaults to `.standard`.
    init(resolver: Resolver, userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
        injectServices(resolver)

        // FIXME: this can be removed in later releases
        migrateFromLegacyJSONIfNeeded()

        unacknowledgedAlertsPublisher.send(unacknowledgedAlertsWithinLast24Hours().isNotEmpty)
    }

    /// Stores a new alert entry and notifies observers.
    ///
    /// The history is:
    /// - de-duplicated by `issuedDate`
    /// - pruned to the last 24 hours
    /// - sorted with newest first
    ///
    /// After persisting, this updates `unacknowledgedAlertsPublisher` and broadcasts the latest list to `AlertObserver`s.
    /// - Parameter alert: The alert to store.
    func addAlert(_ alert: AlertEntry) {
        processQueue.sync {
            var all = loadAll()
            all.append(alert)

            let uniqEvents = pruneAndSort(dedupeByIssuedDate(all))
            saveAll(uniqEvents)

            unacknowledgedAlertsPublisher.send(self.unacknowledgedAlertsWithinLast24HoursOnQueue().isNotEmpty)
            broadcaster.notify(AlertObserver.self, on: processQueue) {
                $0.AlertDidUpdate(uniqEvents)
            }
        }
    }

    /// Returns the baseline sync date used by the alert subsystem.
    ///
    /// This matches the previous behavior: one day ago from "now".
    func syncDate() -> Date {
        Date().addingTimeInterval(-1.days.timeInterval)
    }

    /// Returns all unacknowledged alerts from the last 24 hours, sorted newest first.
    func unacknowledgedAlertsWithinLast24Hours() -> [AlertEntry] {
        processQueue.sync {
            self.unacknowledgedAlertsWithinLast24HoursOnQueue()
        }
    }

    /// Returns all unacknowledged alerts from the last 24 hours, sorted newest first.
    /// - Important: Must only be called while already executing on `processQueue`.
    private func unacknowledgedAlertsWithinLast24HoursOnQueue() -> [AlertEntry] {
        loadAll()
            .filter { $0.issuedDate.addingTimeInterval(1.days.timeInterval) > Date() && $0.acknowledgedDate == nil }
            .sorted { $0.issuedDate > $1.issuedDate }
    }

    /// Acknowledges an alert (by issued date), or stores an error for it.
    ///
    /// If `error` is non-nil, the alert is updated with `errorMessage`.
    /// Otherwise, the alert is marked as acknowledged by setting `acknowledgedDate = Date()`.
    ///
    /// After persisting, this updates `unacknowledgedAlertsPublisher`.
    /// - Parameters:
    ///   - issuedAt: The issued date of the alert entry to update.
    ///   - error: Optional error message to store instead of acknowledging.
    func acknowledgeAlert(_ issuedAt: Date, _ error: String?) {
        processQueue.sync {
            var all = loadAll()
            guard let idx = all.firstIndex(where: { $0.issuedDate == issuedAt }) else { return }

            if let error {
                all[idx].errorMessage = error
            } else {
                all[idx].acknowledgedDate = Date()
            }

            let cleaned = pruneAndSort(dedupeByIssuedDate(all))
            saveAll(cleaned)
            unacknowledgedAlertsPublisher.send(self.unacknowledgedAlertsWithinLast24HoursOnQueue().isNotEmpty)
        }
    }

    /// Deletes an alert entry by its identifier and notifies observers.
    ///
    /// After persisting, this updates `unacknowledgedAlertsPublisher` and broadcasts the updated list.
    /// - Parameter identifier: The `alertIdentifier` of the entry to delete.
    func removeAlert(identifier: String) {
        processQueue.sync {
            var all = loadAll()
            guard let idx = all.firstIndex(where: { $0.alertIdentifier == identifier }) else { return }

            all.remove(at: idx)

            let cleaned = pruneAndSort(dedupeByIssuedDate(all))
            saveAll(cleaned)

            unacknowledgedAlertsPublisher.send(self.unacknowledgedAlertsWithinLast24HoursOnQueue().isNotEmpty)
            broadcaster.notify(AlertObserver.self, on: processQueue) {
                $0.AlertDidUpdate(cleaned)
            }
        }
    }

    /// Forces a broadcast of the current alert list (last 24 hours) to observers.
    ///
    /// This does not modify the data; it only re-emits state via `unacknowledgedAlertsPublisher` and `AlertObserver`.
    func broadcastAlertUpdates() {
        processQueue.sync {
            let uniqEvents = pruneAndSort(loadAll())
            unacknowledgedAlertsPublisher.send(self.unacknowledgedAlertsWithinLast24HoursOnQueue().isNotEmpty)
            broadcaster.notify(AlertObserver.self, on: processQueue) {
                $0.AlertDidUpdate(uniqEvents)
            }
        }
    }

    // MARK: - Migration

    /// Migrates alert history from the legacy on-disk JSON file into UserDefaults.
    ///
    /// Migration behavior:
    /// - Runs at most once per install (guarded by `Keys.alertsMigrationDone`).
    /// - If the new UserDefaults value already exists, migration is considered complete.
    /// - If legacy alerts exist, they are normalized (dedupe/prune/sort) and stored in UserDefaults.
    /// - After a successful migration, the legacy file is removed to avoid future drift.
    private func migrateFromLegacyJSONIfNeeded() { // FIXME: this can be removed in later releases
        processQueue.sync {
            // Avoid repeated disk reads forever
            if defaults.bool(forKey: Keys.alertsMigrationDone) { return }

            // If new store already has data, consider migration done
            if defaults.data(forKey: Keys.alertsData) != nil {
                defaults.set(true, forKey: Keys.alertsMigrationDone)
                return
            }

            // Read legacy file ("monitor/alerthistory.json") via existing FileStorage
            let legacyJsonAlerts = fileStorage.retrieve(OpenAPS.Monitor.alertHistory, as: [AlertEntry].self) ?? []
            guard legacyJsonAlerts.isNotEmpty else {
                defaults.set(true, forKey: Keys.alertsMigrationDone)
                return
            }

            // Normalize before persisting
            let migrated = pruneAndSort(dedupeByIssuedDate(legacyJsonAlerts))
            saveAll(migrated)

            // Mark complete FIRST, then cleanup
            defaults.set(true, forKey: Keys.alertsMigrationDone)

            // Cleanup: remove legacy json so it cannot drift / get re-used accidentally
            fileStorage.remove(OpenAPS.Monitor.alertHistory)
        }
    }

    // MARK: - UserDefaults persistence

    // Uses the same encoder/decoder as file storage to keep Date encoding consistent.

    /// Loads all persisted alerts from UserDefaults.
    ///
    /// Decoding uses `JSONCoding.decoder` to match the previous on-disk JSON encoding/decoding behavior.
    /// If decoding fails, the stored payload is removed so the app can recover cleanly.
    private func loadAll() -> [AlertEntry] {
        guard let data = defaults.data(forKey: Keys.alertsData) else { return [] }
        do {
            return try JSONCoding.decoder.decode([AlertEntry].self, from: data)
        } catch {
            debug(.storage, "Failed to decode alerts from UserDefaults: \(error)")
            // Clear corrupt payload so app can recover
            defaults.removeObject(forKey: Keys.alertsData)
            return []
        }
    }

    /// Persists all alerts to UserDefaults.
    ///
    /// Encoding uses `JSONCoding.encoder` to match the previous on-disk JSON encoding behavior.
    private func saveAll(_ alerts: [AlertEntry]) {
        do {
            let data = try JSONCoding.encoder.encode(alerts)
            defaults.set(data, forKey: Keys.alertsData)
        } catch {
            debug(.storage, "Failed to encode alerts to UserDefaults: \(error)")
        }
    }

    // MARK: - Helpers

    /// Filters the provided alerts to the last 24 hours and sorts them with newest first.
    private func pruneAndSort(_ alerts: [AlertEntry]) -> [AlertEntry] {
        alerts
            .filter { $0.issuedDate.addingTimeInterval(1.days.timeInterval) > Date() }
            .sorted { $0.issuedDate > $1.issuedDate }
    }

    /// De-duplicates alert entries by `issuedDate` (keeping the newest occurrence when duplicates exist).
    ///
    /// This matches `AlertEntry`'s `Equatable`/`Hashable` semantics (both based on `issuedDate`).
    private func dedupeByIssuedDate(_ alerts: [AlertEntry]) -> [AlertEntry] {
        var seen = Set<Date>()
        var result: [AlertEntry] = []
        for item in alerts.sorted(by: { $0.issuedDate > $1.issuedDate }) {
            if seen.insert(item.issuedDate).inserted {
                result.append(item)
            }
        }
        return result
    }
}
