import CoreData
import Foundation
import UIKit

/// Handles intent requests related to temporary presets, such as fetching, enacting, and canceling temp targets.
final class TempPresetsIntentRequest: BaseIntentsRequest {
    /// Enum representing possible errors related to temporary presets.
    enum TempPresetsError: Error {
        case noTempTargetFound
        case noDurationDefined
    }

    /// Fetches and processes all available temporary target presets.
    ///
    /// - Returns: An array of `TempPreset` objects.
    /// - Throws: An error if fetching or processing fails.
    func fetchAndProcessTempTargets() async throws -> [TempPreset] {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "fetchAndProcessTempTargets"

        // Fetch all Temp Target Presets via TempTargetStorage
        let allTempTargetPresetsIDs = try await tempTargetsStorage.fetchForTempTargetPresets()

        // Perform the fetch and process on the Core Data context's thread
        return try await context.perform {
            // Fetch existing TempTargetStored objects based on their NSManagedObjectIDs
            let tempTargetObjects: [TempTargetStored] = allTempTargetPresetsIDs.compactMap { id in
                guard let object = try? context.existingObject(with: id) as? TempTargetStored else {
                    warning(.treatments, "Skipped temp target preset that could not be loaded")
                    return nil
                }
                return object
            }

            // Map fetched TempTargetStored objects to TempPreset
            return try tempTargetObjects.compactMap { object in
                guard let id = object.id,
                      let name = object.name,
                      let target = object.target?.decimalValue,
                      let duration = object.duration?.decimalValue
                else {
                    debug(.treatments, "Temp target preset is missing required fields")
                    throw TempPresetsError.noTempTargetFound
                }
                return TempPreset(id: id, name: name, targetTop: target, duration: duration)
            }
        }
    }

    /// Fetches temporary target presets based on the given identifiers.
    ///
    /// - Parameter uuid: An array of preset IDs to fetch.
    /// - Returns: An array of `TempPreset` objects.
    func fetchIDs(_ uuid: [TempPreset.ID]) async -> [TempPreset] {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "fetchIDs"

        return await context.perform {
            let fetchRequest: NSFetchRequest<TempTargetStored> = TempTargetStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", uuid)

            do {
                let result = try context.fetch(fetchRequest)

                if result.isEmpty {
                    debug(.treatments, "No temp target presets found for \(uuid.count) IDs")
                    return [TempPreset(id: UUID(), name: "", duration: 0)]
                }

                return result.map { tempTargetStored in
                    TempPreset(
                        id: tempTargetStored.id ?? UUID(),
                        name: tempTargetStored.name ?? "",
                        duration: tempTargetStored.duration as? Decimal ?? 0
                    )
                }
            } catch let error as NSError {
                warning(.treatments, "Fetching temp target presets failed", error: error)
                return [TempPreset(id: UUID(), name: "", duration: 0)]
            }
        }
    }

    /// Enacts a temporary target preset. The adjustment manager ends whatever runs, records its run
    /// entry, enables the preset, hands oref the new entry and uploads the change to Nightscout
    /// before returning.
    ///
    /// - Parameter preset: The `TempPreset` to apply.
    /// - Returns: `true` if successfully enacted, otherwise `false`.
    @MainActor func enactTempTarget(_ preset: TempPreset) async -> Bool {
        debug(.treatments, "Starting temp target \(preset.name) from shortcut")
        var backgroundTaskID = startBackgroundTask(withName: "TempTarget Enact")
        defer { endBackgroundTaskSafely(&backgroundTaskID, taskName: "TempTarget Enact") }

        do {
            try await adjustmentManager.activateTempTarget(
                .presetID(preset.id.uuidString),
                source: .shortcut,
                waitForUpload: true
            )
            debug(.treatments, "Temp target started from shortcut")
            return true
        } catch {
            warning(.treatments, "Starting temp target from shortcut failed", error: error)
            return false
        }
    }

    /// Cancels the active temporary target. Nothing running is the state the intent asks for.
    @MainActor func cancelTempTarget() async {
        debug(.treatments, "Stopping temp target from shortcut")
        var backgroundTaskID = startBackgroundTask(withName: "TempTarget Cancel")
        defer { endBackgroundTaskSafely(&backgroundTaskID, taskName: "TempTarget Cancel") }

        do {
            try await adjustmentManager.cancelTempTarget(source: .shortcut, waitForUpload: true)
        } catch AdjustmentError.nothingActive {
            debug(.treatments, "No active temp target to stop")
        } catch {
            warning(.treatments, "Stopping temp target from shortcut failed", error: error)
        }
    }
}
