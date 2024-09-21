import CoreData
import Foundation
import UIKit

@available(iOS 16.0, *) final class OverridePresetsIntentRequest: BaseIntentsRequest {
    enum overridePresetsError: Error {
        case noTempOverrideFound
        case noDurationDefined
        case noActiveOverride
    }

    func fetchAndProcessOverrides() async -> [OverridePreset] {
        // Fetch all Override Presets via OverrideStorage
        let allOverridePresetsIDs = await overrideStorage.fetchForOverridePresets()

        // Since we are fetching on a different background Thread we need to unpack the NSManagedObjectID on the correct Thread first
        return await coredataContext.perform {
            do {
                let overrideObjects = try allOverridePresetsIDs.compactMap { id in
                    try self.coredataContext.existingObject(with: id) as? OverrideStored
                }

                return overrideObjects.map { object in
                    guard let id = object.id,
                          let name = object.name else { return OverridePreset(id: UUID().uuidString, name: "") }
                    return OverridePreset(id: id, name: name)
                }

            } catch {
                debugPrint(
                    "\(#file) \(#function) \(DebuggingIdentifiers.failed) error while fetching/ processing the overrides Array: \(error.localizedDescription)"
                )
                return [OverridePreset(id: UUID().uuidString, name: "")]
            }
        }
    }

    func fetchIDs(_ uuid: [OverridePreset.ID]) async -> [OverridePreset] {
        await coredataContext.perform {
            let fetchRequest: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", uuid)

            do {
                let result = try self.coredataContext.fetch(fetchRequest)

                if result.isEmpty {
                    debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) No OverrideStored found for ids: \(uuid)")
                    return [OverridePreset(id: UUID().uuidString, name: "")]
                }

                return result.map { overrideStored in
                    OverridePreset(id: overrideStored.id ?? UUID().uuidString, name: overrideStored.name ?? "")
                }
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to fetch Override: \(error.localizedDescription)"
                )
                return [OverridePreset(id: UUID().uuidString, name: "")]
            }
        }
    }

    private func fetchOverrideID(_ preset: OverridePreset) async -> NSManagedObjectID? {
        let fetchRequest: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", preset.id)
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

    @MainActor func enactOverride(_ preset: OverridePreset) async -> Bool {
        // Start background task to ensure that the task can run in background mode
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = await UIApplication.shared.beginBackgroundTask(withName: "Override Upload") {
            guard backgroundTaskID != .invalid else { return }
            Task {
                // End background task when the time is about to expire
                await UIApplication.shared.endBackgroundTask(backgroundTaskID)
            }
            backgroundTaskID = .invalid
        }

        do {
            guard let overrideID = await fetchOverrideID(preset),
                  let overrideObject = try viewContext.existingObject(with: overrideID) as? OverrideStored
            else {
                // Be sure to end background task if error occurs
                await UIApplication.shared.endBackgroundTask(backgroundTaskID)
                return false
            }

            // Enable Override
            overrideObject.enabled = true
            overrideObject.date = Date()
            overrideObject.isUploadedToNS = false

            // Disable previous overrides if necessary
            await disableAllActiveOverrides(except: overrideID, createOverrideRunEntry: true)

            if viewContext.hasChanges {
                try viewContext.save()

                // Update State variables in OverrideView
                Foundation.NotificationCenter.default.post(name: .willUpdateOverrideConfiguration, object: nil)

                // Await the notification
                print("Waiting for notification...")
                await awaitNotification(.didUpdateOverrideConfiguration)
                print("Notification received, continuing...")

                // End background task after everything is done
                await UIApplication.shared.endBackgroundTask(backgroundTaskID)
                return true
            }
        } catch {
            // Handle error and ensure background task is ended
            debugPrint("Failed to enact Override: \(error.localizedDescription)")
            await UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }

        // Make sure background task ends in any case
        await UIApplication.shared.endBackgroundTask(backgroundTaskID)
        return false
    }

    func cancelOverride() async {
        await disableAllActiveOverrides(createOverrideRunEntry: true)
    }

    @MainActor func disableAllActiveOverrides(
        except overrideID: NSManagedObjectID? = nil,
        createOverrideRunEntry _: Bool
    ) async {
        // Get ALL NSManagedObject IDs of ALL active Overrides to cancel every single Override
        let ids = await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 0) // 0 = no fetch limit

        await viewContext.perform {
            do {
                // Fetch the existing OverrideStored objects from the context
                let results = try ids.compactMap { id in
                    try self.viewContext.existingObject(with: id) as? OverrideStored
                }

                // If there are no results, return early
                guard !results.isEmpty else { return }

                // Check if we also need to create a corresponding OverrideRunStored entry, i.e. when the User uses the Cancel Button in Override View
                // Auggie - commented out this if statment, we always need to do this for overrides
                // if createOverrideRunEntry {
                // Use the first override to create a new OverrideRunStored entry
                if let canceledOverride = results.first {
                    let newOverrideRunStored = OverrideRunStored(context: self.viewContext)
                    newOverrideRunStored.id = UUID()
                    newOverrideRunStored.name = canceledOverride.name
                    newOverrideRunStored.startDate = canceledOverride.date ?? .distantPast
                    newOverrideRunStored.endDate = Date()
                    newOverrideRunStored
                        .target = NSDecimalNumber(
                            decimal: self.overrideStorage
                                .calculateTarget(override: canceledOverride)
                        )
                    newOverrideRunStored.override = canceledOverride
                    newOverrideRunStored.isUploadedToNS = false
                }
                // }

                // Disable all override except the one with overrideID
                for overrideToCancel in results {
                    if overrideToCancel.objectID != overrideID {
                        overrideToCancel.enabled = false
                        overrideToCancel.isUploadedToNS = false
                    }
                }

                // Save the context if there are changes
                if self.viewContext.hasChanges {
                    try self.viewContext.save()

                    // Update State variables in OverrideView
                    Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
                }
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to disable active Overrides with error: \(error.localizedDescription)"
                )
            }
        }
    }
}
