import CoreData
import Foundation
import UIKit

final class TempPresetsIntentRequest: BaseIntentsRequest {
    enum TempPresetsError: Error {
        case noTempTargetFound
        case noDurationDefined
    }

    private var intentSuccess: Bool = false

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
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to fetch TempTarget: \(error.localizedDescription)"
                )
                return [TempPreset(id: UUID(), name: "", duration: 0)]
            }
        }
    }

    private func fetchTempTargetID(_ preset: TempPreset) async -> NSManagedObjectID? {
        let fetchRequest: NSFetchRequest<TempTargetStored> = TempTargetStored.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", preset.id.uuidString)
        fetchRequest.fetchLimit = 1

        return await coredataContext.perform {
            do {
                return try self.coredataContext.fetch(fetchRequest).first?.objectID
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to fetch Temp Target: \(error.localizedDescription)"
                )
                return nil
            }
        }
    }

    @MainActor func enactTempTarget(_ preset: TempPreset) async -> Bool {
        debug(.default, "Enacting Temp Target: \(preset.name)")
        intentSuccess = false

        // Start background task
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = startBackgroundTask(withName: "TempTarget Enact")

        // Disable previous overrides if necessary, without starting a background task
        await disableAllActiveTempTargets(shouldStartBackgroundTask: false)

        do {
            // Get NSManagedObjectID of Preset
            guard let tempTargetID = await fetchTempTargetID(preset),
                  let tempTargetObject = try viewContext.existingObject(with: tempTargetID) as? TempTargetStored
            else { return false }

            // Enable TempTarget
            tempTargetObject.enabled = true
            tempTargetObject.date = Date()
            tempTargetObject.isUploadedToNS = false

            if viewContext.hasChanges {
                debug(.default, "Saving changes...")

                try viewContext.save()

                // Update State variables in TempTargetView
                Foundation.NotificationCenter.default.post(name: .willUpdateTempTargetConfiguration, object: nil)

                // Await the notification
                debug(.default, "Waiting for notification...")

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
            // Handle error and ensure background task is ended
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to enact Temp Targett with error: \(error.localizedDescription)"
            )

            endBackgroundTaskSafely(&backgroundTaskID, taskName: "TempTarget Enact")

            intentSuccess = false
            return intentSuccess
        }
    }

    func cancelTempTarget() async {
        await disableAllActiveTempTargets(shouldStartBackgroundTask: true)
        tempTargetsStorage.saveTempTargetsToStorage([TempTarget.cancel(at: Date().addingTimeInterval(-1))])
    }

    @MainActor func disableAllActiveTempTargets(shouldStartBackgroundTask: Bool = true) async {
        var backgroundTaskID: UIBackgroundTaskIdentifier?

        if shouldStartBackgroundTask {
            // Start background task
            backgroundTaskID = .invalid
            backgroundTaskID = startBackgroundTask(withName: "TempTarget Cancel")
        }

        do {
            // Get NSManagedObjectID of all active temp Targets
            let ids = try await tempTargetsStorage.loadLatestTempTargetConfigurations(fetchLimit: 0)
            // Fetch existing OverrideStored objects
            let results = try ids.compactMap { id in
                try self.viewContext.existingObject(with: id) as? TempTargetStored
            }

            // Return early if no results
            guard !results.isEmpty else {
                debug(.default, "No active temp targets to cancel... returning early")

                if var backgroundTaskID = backgroundTaskID {
                    debug(.default, "Ending background task for temp target cancel")
                    endBackgroundTaskSafely(&backgroundTaskID, taskName: "TempTarget Cancel")
                }
                return
            }

            // Create TempTargetRunStored entry
            // Use the first temp target to create a new TempTargetRunStored entry
            if let canceledTempTarget = results.first {
                let newTempTargetRunStored = TempTargetRunStored(context: viewContext)
                newTempTargetRunStored.id = UUID()
                newTempTargetRunStored.name = canceledTempTarget.name
                newTempTargetRunStored.startDate = canceledTempTarget.date ?? .distantPast
                newTempTargetRunStored.endDate = Date()
                newTempTargetRunStored
                    .target = canceledTempTarget.target ?? 0
                newTempTargetRunStored.tempTarget = canceledTempTarget
                newTempTargetRunStored.isUploadedToNS = false
            }

            // Disable all override except the one with overrideID
            for tempTargetToCancel in results {
                tempTargetToCancel.enabled = false
                tempTargetToCancel.isUploadedToNS = false
            }

            if viewContext.hasChanges {
                try viewContext.save()

                // Update State variables in OverrideView
                Foundation.NotificationCenter.default.post(name: .willUpdateTempTargetConfiguration, object: nil)
            }

            // Await the notification
            // Await the notification
            debug(.default, "Waiting for notification...")

            await awaitNotification(.didUpdateOverrideConfiguration)

            debug(.default, "Notification received, continuing...")

            if var backgroundTaskID = backgroundTaskID {
                debug(.default, "Ending background task for temp target cancel")
                endBackgroundTaskSafely(&backgroundTaskID, taskName: "TempTarget Cancel")
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to disable active Temp Targets with error: \(error.localizedDescription)"
            )

            if var backgroundTaskID = backgroundTaskID {
                debug(.default, "Ending background task for temp target cancel")
                endBackgroundTaskSafely(&backgroundTaskID, taskName: "TempTarget Cancel")
            }
        }
    }
}
