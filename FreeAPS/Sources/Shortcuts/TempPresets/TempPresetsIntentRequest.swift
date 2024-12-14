import CoreData
import Foundation
import UIKit

final class TempPresetsIntentRequest: BaseIntentsRequest {
    enum TempPresetsError: Error {
        case noTempTargetFound
        case noDurationDefined
    }

    func fetchAndProcessTempTargets() async -> [TempPreset] {
        // Fetch all Temp Target Presets via TempTargetStorage
        let allTempTargetPresetsIDs = await tempTargetsStorage.fetchForTempTargetPresets()

        // Perform the fetch and process on the Core Data context's thread
        return await coredataContext.perform {
            // Fetch existing TempTargetStored objects based on their NSManagedObjectIDs
            let tempTargetObjects: [TempTargetStored] = allTempTargetPresetsIDs.compactMap { id in
                guard let object = try? self.coredataContext.existingObject(with: id) as? TempTargetStored else {
                    debugPrint("\(#file) \(#function) Failed to fetch object for ID: \(id)")
                    return nil
                }
                return object
            }

            // Map fetched TempTargetStored objects to TempPreset
            return tempTargetObjects.compactMap { object in
                guard let id = object.id,
                      let name = object.name,
                      let target = object.target?.decimalValue,
                      let duration = object.duration?.decimalValue
                else {
                    debugPrint("\(#file) \(#function) Missing data for TempTargetStored object.")
                    return TempPreset(id: UUID(), name: "", duration: 0)
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
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to fetch Override: \(error.localizedDescription)"
                )
                return nil
            }
        }
    }

    @MainActor func enactTempTarget(_ preset: TempPreset) async -> Bool {
        // Start background task
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Override Upload") {
            guard backgroundTaskID != .invalid else { return }
            Task {
                // End background task when the time is about to expire
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
            }
            backgroundTaskID = .invalid
        }

        // Defer block to end background task when function exits
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
            guard let tempTargetID = await fetchTempTargetID(preset),
                  let tempTargetObject = try viewContext.existingObject(with: tempTargetID) as? TempTargetStored
            else { return false }

            // Enable TempTarget
            tempTargetObject.enabled = true
            tempTargetObject.date = Date()
            tempTargetObject.isUploadedToNS = false

            // Disable previous overrides if necessary, without starting a background task
            await disableAllActiveTempTargets(
                except: tempTargetID,
                createTempTargetRunEntry: true,
                shouldStartBackgroundTask: false
            )

            if viewContext.hasChanges {
                try viewContext.save()

                // Update State variables in TempTargetView
                Foundation.NotificationCenter.default.post(name: .willUpdateTempTargetConfiguration, object: nil)

                // Await the notification
                print("Waiting for notification...")

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
                print("Notification received, continuing...")

                return true
            }
        } catch {
            // Handle error and ensure background task is ended
            debugPrint("Failed to enact TempTarget: \(error.localizedDescription)")
        }

        return false
    }

    func cancelTempTarget() async {
        await disableAllActiveTempTargets(createTempTargetRunEntry: true, shouldStartBackgroundTask: true)
    }

    @MainActor func disableAllActiveTempTargets(
        except tempTargetID: NSManagedObjectID? = nil,
        createTempTargetRunEntry: Bool,
        shouldStartBackgroundTask: Bool = true
    ) async {
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

        if shouldStartBackgroundTask {
            // Start background task
            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "TempTarget Cancel") {
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

        // Get NSManagedObjectID of all active temp Targets
        let ids = await tempTargetsStorage.loadLatestTempTargetConfigurations(fetchLimit: 0)

        do {
            // Fetch existing OverrideStored objects
            let results = try ids.compactMap { id in
                try self.viewContext.existingObject(with: id) as? TempTargetStored
            }

            // Return early if no results
            guard !results.isEmpty else { return }

            // Create TempTargetRunStored entry if needed
            if createTempTargetRunEntry {
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
            }

            // Disable all override except the one with overrideID
            for tempTargetToCancel in results {
                if tempTargetToCancel.objectID != tempTargetID {
                    tempTargetToCancel.enabled = false
                    tempTargetToCancel.isUploadedToNS = false
                }
            }

            if viewContext.hasChanges {
                try viewContext.save()

                // Update State variables in OverrideView
                Foundation.NotificationCenter.default.post(name: .willUpdateTempTargetConfiguration, object: nil)
            }

            // Await the notification
            print("Waiting for notification...")
            await awaitNotification(.didUpdateTempTargetConfiguration)
            print("Notification received, continuing...")

        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to disable active Temp Targets with error: \(error.localizedDescription)"
            )
        }
    }
}
