import CoreData
import Foundation
import UIKit

@available(iOS 16.0, *) final class OverridePresetsIntentRequest: BaseIntentsRequest {
    enum overridePresetsError: Error {
        case noTempOverrideFound
        case noDurationDefined
        case noActiveOverride
    }

    func fetchAndProcessOverrides() async throws -> [OverridePreset] {
        do {
            // Fetch all Override Presets via OverrideStorage
            let allOverridePresetsIDs = try await overrideStorage.fetchForOverridePresets()

            // Since we are fetching on a different background Thread we need to unpack the NSManagedObjectID on the correct Thread first
            return try await coredataContext.perform {
                let overrideObjects = try allOverridePresetsIDs.compactMap { id in
                    try self.coredataContext.existingObject(with: id) as? OverrideStored
                }

                return overrideObjects.map { object in
                    guard let id = object.id,
                          let name = object.name else { return OverridePreset(id: UUID().uuidString, name: "") }
                    return OverridePreset(id: id, name: name)
                }
            }
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Error fetching/processing overrides: \(error.localizedDescription)"
            )
            throw error
        }
    }

    func fetchIDs(_ uuid: [OverridePreset.ID]) async throws -> [OverridePreset] {
        try await coredataContext.perform {
            let fetchRequest: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", uuid)

            do {
                let result = try self.coredataContext.fetch(fetchRequest)

                if result.isEmpty {
                    debug(
                        .default,
                        "\(DebuggingIdentifiers.failed) No OverrideStored found for ids: \(uuid)"
                    )
                    throw overridePresetsError.noTempOverrideFound
                }

                return result.map { overrideStored in
                    OverridePreset(id: overrideStored.id ?? UUID().uuidString, name: overrideStored.name ?? "")
                }
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Failed to fetch Override: \(error.localizedDescription)"
                )
                throw error
            }
        }
    }

    private func fetchOverrideID(_ preset: OverridePreset) async throws -> NSManagedObjectID {
        let fetchRequest: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", preset.id)
        fetchRequest.fetchLimit = 1

        return try await coredataContext.perform {
            guard let objectID = try self.coredataContext.fetch(fetchRequest).first?.objectID else {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) No override found for preset: \(preset.name)"
                )
                throw overridePresetsError.noTempOverrideFound
            }
            return objectID
        }
    }

    @MainActor func enactOverride(_ preset: OverridePreset) async -> Bool {
        // Start background task
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Override Upload") {
            guard backgroundTaskID != .invalid else { return }
            Task {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
            }
            backgroundTaskID = .invalid
        }

        defer {
            if backgroundTaskID != .invalid {
                Task {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
                backgroundTaskID = .invalid
            }
        }

        do {
            // Get NSManagedObjectID of Preset
            let overrideID = try await fetchOverrideID(preset)
            guard let overrideObject = try viewContext.existingObject(with: overrideID) as? OverrideStored else {
                throw overridePresetsError.noTempOverrideFound
            }

            // Enable Override
            overrideObject.enabled = true
            overrideObject.date = Date()
            overrideObject.isUploadedToNS = false

            // Disable previous overrides if necessary
            await disableAllActiveOverrides(except: overrideID, createOverrideRunEntry: true, shouldStartBackgroundTask: false)

            if viewContext.hasChanges {
                try viewContext.save()
                Foundation.NotificationCenter.default.post(name: .willUpdateOverrideConfiguration, object: nil)
                await awaitNotification(.didUpdateOverrideConfiguration)
                return true
            }
            return false
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to enact override: \(error.localizedDescription)"
            )
            return false
        }
    }

    func cancelOverride() async {
        await disableAllActiveOverrides(createOverrideRunEntry: true, shouldStartBackgroundTask: true)
    }

    @MainActor func disableAllActiveOverrides(
        except overrideID: NSManagedObjectID? = nil,
        createOverrideRunEntry: Bool,
        shouldStartBackgroundTask: Bool = true
    ) async {
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

        if shouldStartBackgroundTask {
            // Start background task
            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Override Cancel") {
                guard backgroundTaskID != .invalid else { return }
                Task {
                    // End background task when the time is about to expire
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
                backgroundTaskID = .invalid
            }
        }

        // Defer block to end background task when function exits, only if it was started
        defer {
            if shouldStartBackgroundTask, backgroundTaskID != .invalid {
                Task {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
                backgroundTaskID = .invalid
            }
        }

        do {
            // Get NSManagedObjectID of all active overrides
            let ids = try await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 0) // 0 = no fetch limit
            // Fetch existing OverrideStored objects
            let results = try ids.compactMap { id in
                try self.viewContext.existingObject(with: id) as? OverrideStored
            }

            // Return early if no results
            guard !results.isEmpty else { return }

            // Create OverrideRunStored entry if needed
            if createOverrideRunEntry, let canceledOverride = results.first {
                let newOverrideRunStored = OverrideRunStored(context: viewContext)
                newOverrideRunStored.id = UUID()
                newOverrideRunStored.name = canceledOverride.name
                newOverrideRunStored.startDate = canceledOverride.date ?? .distantPast
                newOverrideRunStored.endDate = Date()
                newOverrideRunStored.target = NSDecimalNumber(
                    decimal: overrideStorage.calculateTarget(override: canceledOverride)
                )
                newOverrideRunStored.override = canceledOverride
                newOverrideRunStored.isUploadedToNS = false
            }

            // Disable all overrides except the one specified
            for overrideToCancel in results {
                if overrideToCancel.objectID != overrideID {
                    overrideToCancel.enabled = false
                    overrideToCancel.isUploadedToNS = false
                }
            }

            if viewContext.hasChanges {
                try viewContext.save()

                // Update State variables in OverrideView
                Foundation.NotificationCenter.default.post(name: .willUpdateOverrideConfiguration, object: nil)
            }

            // Await the notification
            print("Waiting for notification...")
            await awaitNotification(.didUpdateOverrideConfiguration)
            print("Notification received, continuing...")

        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to disable active Overrides with error: \(error.localizedDescription)"
            )
        }
    }
}
