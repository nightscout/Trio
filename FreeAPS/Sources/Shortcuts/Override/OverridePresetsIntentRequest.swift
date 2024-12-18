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
        // Start background task
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = await UIApplication.shared.beginBackgroundTask(withName: "Override Upload") {
            guard backgroundTaskID != .invalid else { return }
            Task {
                // End background task when the time is about to expire
                await UIApplication.shared.endBackgroundTask(backgroundTaskID)
            }
            backgroundTaskID = .invalid
        }

        // Defer block to end background task when function exits
        defer {
            if backgroundTaskID != .invalid {
                Task {
                    await UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
                backgroundTaskID = .invalid
            }
        }

        do {
            // Get NSManagedObjectID of Preset
            guard let overrideID = await fetchOverrideID(preset),
                  let overrideObject = try viewContext.existingObject(with: overrideID) as? OverrideStored
            else { return false }

            // Enable Override
            overrideObject.enabled = true
            overrideObject.date = Date()
            overrideObject.isUploadedToNS = false

            // Disable previous overrides if necessary, without starting a background task
            await disableAllActiveOverrides(except: overrideID, createOverrideRunEntry: true, shouldStartBackgroundTask: false)

            if viewContext.hasChanges {
                try viewContext.save()

                // Update State variables in OverrideView
                Foundation.NotificationCenter.default.post(name: .willUpdateOverrideConfiguration, object: nil)

                // Await the notification
                print("Waiting for notification...")
                await awaitNotification(.didUpdateOverrideConfiguration)
                print("Notification received, continuing...")

                return true
            }
        } catch {
            // Handle error and ensure background task is ended
            debugPrint("Failed to enact Override: \(error.localizedDescription)")
        }

        return false
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
            backgroundTaskID = await UIApplication.shared.beginBackgroundTask(withName: "Override Cancel") {
                guard backgroundTaskID != .invalid else { return }
                Task {
                    // End background task when the time is about to expire
                    await UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
                backgroundTaskID = .invalid
            }
        }

        // Defer block to end background task when function exits, only if it was started
        defer {
            if shouldStartBackgroundTask, backgroundTaskID != .invalid {
                Task {
                    await UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
                backgroundTaskID = .invalid
            }
        }

        // Get NSManagedObjectID of all active overrides
        let ids = await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 0) // 0 = no fetch limit

        do {
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
