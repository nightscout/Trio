import CoreData
import Foundation
import UIKit

@available(iOS 16.0, *) final class OverridePresetsIntentRequest: BaseIntentsRequest {
    enum overridePresetsError: Error {
        case noTempOverrideFound
        case noDurationDefined
        case noActiveOverride
    }

    /**
     Fetches and processes override presets from Core Data.

     - Returns: An array of `OverridePreset` objects.
     - Throws: An error if fetching fails or Core Data operations fail.
     */
    func fetchAndProcessOverrides() async throws -> [OverridePreset] {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "fetchAndProcessOverrides"

        do {
            // Fetch all Override Presets via OverrideStorage
            let allOverridePresetsIDs = try await overrideStorage.fetchForOverridePresets()

            // Since we are fetching on a different background Thread we need to unpack the NSManagedObjectID on the correct Thread first
            return try await context.perform {
                let overrideObjects = try allOverridePresetsIDs.compactMap { id in
                    try context.existingObject(with: id) as? OverrideStored
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
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "fetchIDs"

        return try await context.perform {
            let fetchRequest: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", uuid)

            do {
                let result = try context.fetch(fetchRequest)

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
     Enacts an override preset. The adjustment manager ends whatever runs, records its run entry,
     enables the preset and uploads the change to Nightscout before returning.

     - Parameter preset: The `OverridePreset` to enact.
     - Returns: A boolean indicating whether the override was successfully enacted.
     */
    @MainActor func enactOverride(_ preset: OverridePreset) async -> Bool {
        debug(.default, "Enacting override: \(preset.name)")
        var backgroundTaskID = startBackgroundTask(withName: "Override Enact")
        defer { endBackgroundTaskSafely(&backgroundTaskID, taskName: "Override Enact") }

        do {
            try await adjustmentManager.activateOverride(.presetID(preset.id), source: .shortcut, waitForUpload: true)
            debug(.default, "Finished. Override enacted via Shortcut.")
            return true
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) Failed to enact override: \(error)")
            return false
        }
    }

    /**
     Cancels the active override. Nothing running is the state the intent asks for.
     */
    @MainActor func cancelOverride() async {
        debug(.default, "Cancelling active override")
        var backgroundTaskID = startBackgroundTask(withName: "Override Cancel")
        defer { endBackgroundTaskSafely(&backgroundTaskID, taskName: "Override Cancel") }

        do {
            try await adjustmentManager.cancelOverride(source: .shortcut, waitForUpload: true)
        } catch AdjustmentError.nothingActive {
            debug(.default, "No active override to cancel")
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) Failed to cancel override: \(error)")
        }
    }
}
