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

    /// Tracks whether the intent execution was successful.
    private var intentSuccess: Bool = false

    /// Fetches and processes all available temporary target presets.
    ///
    /// - Returns: An array of `TempPreset` objects.
    /// - Throws: An error if fetching or processing fails.
    func fetchAndProcessTempTargets() async throws -> [TempPreset] {
        // Fetch all Temp Target Presets via TempTargetStorage
        let allTempTargetPresetsIDs = try await tempTargetsStorage.fetchForTempTargetPresets()

        // Perform the fetch and process on the Core Data context's thread
        return try await coredataContext.perform {
            // Fetch existing TempTargetStored objects based on their NSManagedObjectIDs
            let tempTargetObjects: [TempTargetStored] = allTempTargetPresetsIDs.compactMap { id in
                guard let object = try? self.coredataContext.existingObject(with: id) as? TempTargetStored else {
                    debugPrint("\(#file) \(#function) Failed to fetch object for ID: \(id)")
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
                    debugPrint("\(#file) \(#function) Missing data for TempTargetStored object.")
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
        await coredataContext.perform {
            let fetchRequest: NSFetchRequest<TempTargetStored> = TempTargetStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", uuid)

            do {
                let result = try self.coredataContext.fetch(fetchRequest)

                if result.isEmpty {
                    debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) No TempTargetStored found for ids: \(uuid)")
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
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to fetch TempTarget: \(error)"
                )
                return [TempPreset(id: UUID(), name: "", duration: 0)]
            }
        }
    }

    /// Fetches the `NSManagedObjectID` for a given `TempPreset`.
    ///
    /// - Parameter preset: The `TempPreset` to find.
    /// - Returns: The `NSManagedObjectID` of the temp target if found, otherwise `nil`.
    private func fetchTempTargetID(_ preset: TempPreset) async -> NSManagedObjectID? {
        let fetchRequest: NSFetchRequest<TempTargetStored> = TempTargetStored.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", preset.id.uuidString)
        fetchRequest.fetchLimit = 1

        return await coredataContext.perform {
            do {
                return try self.coredataContext.fetch(fetchRequest).first?.objectID
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to fetch Temp Target: \(error)"
                )
                return nil
            }
        }
    }

    /// Enacts a temporary target preset by updating Core Data and notifying relevant components.
    ///
    /// - Parameter preset: The `TempPreset` to apply.
    /// - Returns: `true` if successfully enacted, otherwise `false`.
    @MainActor func enactTempTarget(_ preset: TempPreset) async -> Bool {
        debug(.default, "Enacting Temp Target: \(preset.name)")
        intentSuccess = false

        // Start background task
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = startBackgroundTask(withName: "TempTarget Enact")

        // Disable previous temp targets if necessary, without starting a background task
        await disableAllActiveTempTargets(shouldStartBackgroundTask: false)

        do {
            // Get NSManagedObjectID of Preset
            guard let tempTargetID = await fetchTempTargetID(preset),
                  let tempTargetObject = try viewContext.existingObject(with: tempTargetID) as? TempTargetStored
            else {
                endBackgroundTaskSafely(&backgroundTaskID, taskName: "TempTarget Enact")
                throw TempPresetsError.noTempTargetFound
            }

            // Enable TempTarget
            tempTargetObject.enabled = true
            tempTargetObject.date = Date()
            tempTargetObject.isUploadedToNS = false

            if viewContext.hasChanges {
                debug(.default, "Saving changes...")
                try viewContext.save()
                debug(.default, "Waiting for notification...")
                // Update State variables in TempTargetView
                Foundation.NotificationCenter.default.post(name: .willUpdateTempTargetConfiguration, object: nil)

                // Prepare JSON for oref
                guard let tempTargetDate = tempTargetObject.date, let tempTarget = tempTargetObject.target,
                      let tempTargetDuration = tempTargetObject.duration else { return false }

                let tempTargetToStoreAsJSON = TempTarget(
                    name: tempTargetObject.name,
                    createdAt: tempTargetDate,
                    targetTop: tempTarget as Decimal,
                    targetBottom: tempTarget as Decimal,
                    duration: tempTargetDuration as Decimal,
                    enteredBy: TempTarget.local,
                    reason: TempTarget.custom,
                    isPreset: tempTargetObject.isPreset,
                    enabled: tempTargetObject.enabled,
                    halfBasalTarget: tempTargetObject.halfBasalTarget as Decimal?
                )
                // Save the temp targets to JSON so that they get used by oref
                tempTargetsStorage.saveTempTargetsToStorage([tempTargetToStoreAsJSON])

                await awaitNotification(.didUpdateTempTargetConfiguration)

                debug(.default, "Notification received, continuing...")
                intentSuccess = true
            }

            endBackgroundTaskSafely(&backgroundTaskID, taskName: "TempTarget Enact")

            debug(.default, "Finished. Temp Target enacted via Shortcut.")

            return intentSuccess
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to enact Temp Target with error: \(error)"
            )

            endBackgroundTaskSafely(&backgroundTaskID, taskName: "TempTarget Enact")

            intentSuccess = false
            return intentSuccess
        }
    }

    /// Cancels an active temporary target.
    func cancelTempTarget() async {
        await disableAllActiveTempTargets(shouldStartBackgroundTask: true)
        tempTargetsStorage.saveTempTargetsToStorage([TempTarget.cancel(at: Date().addingTimeInterval(-1))])
    }

    /// Disables all active temporary targets.
    ///
    /// - Parameter shouldStartBackgroundTask: A flag indicating whether a background task should be started.
    @MainActor func disableAllActiveTempTargets(shouldStartBackgroundTask: Bool) async {
        var backgroundTaskID: UIBackgroundTaskIdentifier?

        if shouldStartBackgroundTask {
            debug(.default, "Starting background task for temp target cancel")
            backgroundTaskID = .invalid
            backgroundTaskID = startBackgroundTask(withName: "TempTarget Cancel")
        }

        do {
            // Fetch active temp targets
            let ids = try await tempTargetsStorage.loadLatestTempTargetConfigurations(fetchLimit: 0)
            let results = try ids.compactMap { id in
                try self.viewContext.existingObject(with: id) as? TempTargetStored
            }

            guard !results.isEmpty else {
                debug(.default, "No active temp targets to cancel... returning early")

                if var backgroundTaskID = backgroundTaskID {
                    debug(.default, "Ending background task for temp target cancel")
                    endBackgroundTaskSafely(&backgroundTaskID, taskName: "TempTarget Cancel")
                }
                return
            }

            // Create a new `TempTargetRunStored` entry
            if let canceledTempTarget = results.first {
                let newTempTargetRunStored = TempTargetRunStored(context: viewContext)
                newTempTargetRunStored.id = UUID()
                newTempTargetRunStored.name = canceledTempTarget.name
                newTempTargetRunStored.startDate = canceledTempTarget.date ?? .distantPast
                newTempTargetRunStored.endDate = Date()
                newTempTargetRunStored.target = canceledTempTarget.target ?? 0
                newTempTargetRunStored.tempTarget = canceledTempTarget
                newTempTargetRunStored.isUploadedToNS = false
            }

            // Disable all temp targets
            for tempTargetToCancel in results {
                tempTargetToCancel.enabled = false
                tempTargetToCancel.isUploadedToNS = false
            }

            if viewContext.hasChanges {
                try viewContext.save()
                debug(.default, "Waiting for notification...")
                Foundation.NotificationCenter.default.post(name: .willUpdateTempTargetConfiguration, object: nil)
                await awaitNotification(.didUpdateTempTargetConfiguration)
                debug(.default, "Notification received, continuing...")
            }

            if var backgroundTaskID = backgroundTaskID {
                debug(.default, "Ending background task for temp target cancel")
                endBackgroundTaskSafely(&backgroundTaskID, taskName: "TempTarget Cancel")
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to disable active Temp Targets with error: \(error)"
            )
            if var backgroundTaskID = backgroundTaskID {
                debug(.default, "Ending background task for temp target cancel")
                endBackgroundTaskSafely(&backgroundTaskID, taskName: "TempTarget Cancel")
            }
        }
    }
}
