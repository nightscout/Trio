import CoreData
import Foundation
import UIKit

@available(iOS 16.0, *) final class OverridePresetsIntentRequest: BaseIntentsRequest {
    enum overridePresetsError: Error {
        case noTempOverrideFound
        case noDurationDefined
        case noActiveOverride
    }

    private var intentSuccess: Bool = false

    /**
     Fetches and processes override presets from Core Data.

     - Returns: An array of `OverridePreset` objects.
     - Throws: An error if fetching fails or Core Data operations fail.
     */
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
                "\(DebuggingIdentifiers.failed) Error fetching/processing overrides: \(error)"
            )
            throw error
        }
    }

    /**
     Fetches override presets by their IDs.

     - Parameter uuid: An array of `OverridePreset.ID` values to fetch.
     - Returns: An array of `OverridePreset` objects matching the provided IDs.
     - Throws: `overridePresetsError.noTempOverrideFound` if no presets are found.
     */
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
                    "\(DebuggingIdentifiers.failed) Failed to fetch Override: \(error)"
                )
                throw error
            }
        }
    }

    /**
     Fetches the Core Data `NSManagedObjectID` for a given `OverridePreset`.

     - Parameter preset: The `OverridePreset` for which to fetch the object ID.
     - Returns: The corresponding `NSManagedObjectID`.
     - Throws: `overridePresetsError.noTempOverrideFound` if the preset is not found.
     */
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

    /**
     Enacts an override preset by enabling it in Core Data and notifying the system.

     - Parameter preset: The `OverridePreset` to enact.
     - Returns: A boolean indicating whether the override was successfully enacted.
     */
    @MainActor func enactOverride(_ preset: OverridePreset) async -> Bool {
        debug(.default, "Enacting override: \(preset.name)")
        intentSuccess = false

        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = startBackgroundTask(withName: "Override Enact")

        await disableAllActiveOverrides(shouldStartBackgroundTask: false)

        do {
            let overrideID = try await fetchOverrideID(preset)
            guard let overrideObject = try viewContext.existingObject(with: overrideID) as? OverrideStored else {
                endBackgroundTaskSafely(&backgroundTaskID, taskName: "Override Enact")
                throw overridePresetsError.noTempOverrideFound
            }

            overrideObject.enabled = true
            overrideObject.date = Date()
            overrideObject.isUploadedToNS = false

            if viewContext.hasChanges {
                debug(.default, "Saving changes...")
                try viewContext.save()
                debug(.default, "Waiting for notification...")
                Foundation.NotificationCenter.default.post(name: .willUpdateOverrideConfiguration, object: nil)
                await awaitNotification(.didUpdateOverrideConfiguration)
                debug(.default, "Notification received, continuing...")
                intentSuccess = true
            }

            endBackgroundTaskSafely(&backgroundTaskID, taskName: "Override Enact")
            debug(.default, "Finished. Override enacted via Shortcut.")
            return intentSuccess
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to enact override: \(error)"
            )
            endBackgroundTaskSafely(&backgroundTaskID, taskName: "Override Enact")
            return false
        }
    }

    /**
     Cancels all active overrides asynchronously.
     */
    func cancelOverride() async {
        await disableAllActiveOverrides(shouldStartBackgroundTask: true)
    }

    /**
     Disables all active overrides and optionally starts a background task.

     - Parameter shouldStartBackgroundTask: A boolean indicating whether to start a background task.
     */
    @MainActor func disableAllActiveOverrides(shouldStartBackgroundTask: Bool) async {
        debug(.default, "Disabling all active overrides")
        var backgroundTaskID: UIBackgroundTaskIdentifier?

        if shouldStartBackgroundTask {
            debug(.default, "Starting background task for override cancel")
            backgroundTaskID = .invalid
            backgroundTaskID = startBackgroundTask(withName: "Override Cancel")
        }

        do {
            // Get NSManagedObjectID of all active overrides
            let ids = try await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 0)
            let results = try ids.compactMap { id in
                try self.viewContext.existingObject(with: id) as? OverrideStored
            }

            // Return early if no results
            guard !results.isEmpty else {
                debug(.default, "No active overrides to cancel… returning early")
                if var backgroundTaskID = backgroundTaskID {
                    debug(.default, "Ending background task for override cancel")
                    endBackgroundTaskSafely(&backgroundTaskID, taskName: "Override Cancel")
                }
                return
            }

            // Create OverrideRunStored entry if needed
            if let canceledOverride = results.first {
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

            // Disable all active overrides
            for overrideToCancel in results {
                let endTime = overrideToCancel.date?
                    .addingTimeInterval(TimeInterval(truncating: overrideToCancel.duration ?? 0))

                debugPrint(
                    "Disabling override: \(overrideToCancel.name ?? "Unnamed") with end time: \(endTime?.description ?? "Unknown")"
                )
                overrideToCancel.enabled = false
                overrideToCancel.isUploadedToNS = false
            }

            if viewContext.hasChanges {
                try viewContext.save()
                debug(.default, "Waiting for notification...")
                Foundation.NotificationCenter.default.post(name: .willUpdateOverrideConfiguration, object: nil)
                await awaitNotification(.didUpdateOverrideConfiguration)
                debug(.default, "Notification received, continuing...")
            }

            if var backgroundTaskID = backgroundTaskID {
                debug(.default, "Ending background task for override cancel")
                endBackgroundTaskSafely(&backgroundTaskID, taskName: "Override Cancel")
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to disable active Overrides with error: \(error)"
            )
            if var backgroundTaskID = backgroundTaskID {
                debug(.default, "Ending background task for override cancel")
                endBackgroundTaskSafely(&backgroundTaskID, taskName: "Override Cancel")
            }
        }
    }
}
