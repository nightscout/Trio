import CoreData
import Foundation
import SwiftDate
import Swinject

protocol TempTargetsObserver {
    func tempTargetsDidUpdate(_ targets: [TempTarget])
}

protocol TempTargetsStorage {
    func storeTempTarget(tempTarget: TempTarget) async
    func saveTempTargetsToStorage(_ targets: [TempTarget])
    func fetchForTempTargetPresets() async -> [NSManagedObjectID]
    func copyRunningTempTarget(_ tempTarget: TempTargetStored) async -> NSManagedObjectID
    func deleteOverridePreset(_ objectID: NSManagedObjectID) async
    func loadLatestTempTargetConfigurations(fetchLimit: Int) async -> [NSManagedObjectID]
    func syncDate() -> Date
    func recent() -> [TempTarget]
    func nightscoutTreatmentsNotUploaded() -> [NightscoutTreatment]
    func presets() -> [TempTarget]
    func current() -> TempTarget?
}

final class BaseTempTargetsStorage: TempTargetsStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseTempTargetsStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!

    private let backgroundContext = CoreDataStack.shared.newTaskContext()
    private let viewContext = CoreDataStack.shared.persistentContainer.viewContext

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func loadLatestTempTargetConfigurations(fetchLimit: Int) async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TempTargetStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.lastActiveTempTarget,
            key: "date",
            ascending: true,
            fetchLimit: fetchLimit
        )

        guard let fetchedResults = results as? [TempTargetStored] else { return [] }

        return await backgroundContext.perform {
            return fetchedResults.map(\.objectID)
        }
    }

    /// Returns the NSManagedObjectID of the Temp Target Presets
    func fetchForTempTargetPresets() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TempTargetStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.allTempTargetPresets,
            key: "date",
            ascending: true
        )

        guard let fetchedResults = results as? [TempTargetStored] else { return [] }

        return await backgroundContext.perform {
            return fetchedResults.map(\.objectID)
        }
    }

    func storeTempTarget(tempTarget: TempTarget) async {
        await backgroundContext.perform {
            let newTempTarget = TempTargetStored(context: self.backgroundContext)
            newTempTarget.date = tempTarget.createdAt
            newTempTarget.id = UUID()
            newTempTarget.enabled = tempTarget.enabled ?? false
            newTempTarget.duration = tempTarget.duration as NSDecimalNumber
            newTempTarget.isUploadedToNS = false
            newTempTarget.name = tempTarget.name
            newTempTarget.target = NSDecimalNumber(decimal: tempTarget.targetTop ?? 0)
            newTempTarget.isPreset = tempTarget.isPreset ?? false

            do {
                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save Temp Target to Core Data with error: \(error.userInfo)"
                )
            }

            /*
             Saving the Preset to the Storage means that it gets used by Oref
             We only want that when either creating a new non-Preset-Temp Target or when enacting a Temp Target Preset, NOT when we are only saving a new Preset, hence the check here!
             */
            if !(tempTarget.isPreset ?? false) {
                self.saveTempTargetsToStorage([tempTarget])
            }
        }
    }

    func saveTempTargetsToStorage(_ targets: [TempTarget]) {
        processQueue.async {
            var updatedTargets = targets

            if let newActive = updatedTargets.last(where: { $0.isActive }) {
                // Cancel current target
                updatedTargets.append(.cancel(at: newActive.createdAt.addingTimeInterval(-1)))
            }

            let file = OpenAPS.Settings.tempTargets

            var uniqEvents: [TempTarget] = []
            self.storage.transaction { storage in
                storage.append(updatedTargets, to: file, uniqBy: \.createdAt)

                let retrievedTargets = storage.retrieve(file, as: [TempTarget].self) ?? []
                uniqEvents = retrievedTargets
                    .filter { $0.isWithinLastDay }
                    .sorted(by: { $0.createdAt > $1.createdAt })

                storage.save(uniqEvents, as: file)
            }

            self.broadcaster.notify(TempTargetsObserver.self, on: self.processQueue) {
                $0.tempTargetsDidUpdate(uniqEvents)
            }
        }
    }

    // Copy the current Temp Target if it is a RUNNING Preset
    /// otherwise we would edit the Preset
    @MainActor func copyRunningTempTarget(_ tempTarget: TempTargetStored) async -> NSManagedObjectID {
        let newTempTarget = TempTargetStored(context: viewContext)
        newTempTarget.date = tempTarget.date
        newTempTarget.id = tempTarget.id
        newTempTarget.enabled = tempTarget.enabled
        newTempTarget.duration = tempTarget.duration
        newTempTarget.isUploadedToNS = true // to avoid getting duplicates on NS
        newTempTarget.name = tempTarget.name
        newTempTarget.target = tempTarget.target
        newTempTarget.isPreset = false // no Preset

        await viewContext.perform {
            do {
                guard self.viewContext.hasChanges else { return }
                try self.viewContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to copy Temp Target with error: \(error.userInfo)"
                )
            }
        }

        return newTempTarget.objectID
    }

    @MainActor func deleteOverridePreset(_ objectID: NSManagedObjectID) async {
        await CoreDataStack.shared.deleteObject(identifiedBy: objectID)
    }

    func syncDate() -> Date {
        Date().addingTimeInterval(-1.days.timeInterval)
    }

    func recent() -> [TempTarget] {
        storage.retrieve(OpenAPS.Settings.tempTargets, as: [TempTarget].self)?.reversed() ?? []
    }

    func current() -> TempTarget? {
        guard let last = recent().last else {
            return nil
        }

        guard last.createdAt.addingTimeInterval(Int(last.duration).minutes.timeInterval) > Date(), last.createdAt <= Date(),
              last.duration != 0
        else {
            return nil
        }

        return last
    }

    func nightscoutTreatmentsNotUploaded() -> [NightscoutTreatment] {
        let uploaded = storage.retrieve(OpenAPS.Nightscout.uploadedTempTargets, as: [NightscoutTreatment].self) ?? []

        let eventsManual = recent().filter { $0.enteredBy == TempTarget.manual }
        let treatments = eventsManual.map {
            NightscoutTreatment(
                duration: Int($0.duration),
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: .nsTempTarget,
                createdAt: $0.createdAt,
                enteredBy: TempTarget.manual,
                bolus: nil,
                insulin: nil,
                notes: nil,
                carbs: nil,
                targetTop: $0.targetTop,
                targetBottom: $0.targetBottom
            )
        }
        return Array(Set(treatments).subtracting(Set(uploaded)))
    }

    func presets() -> [TempTarget] {
        storage.retrieve(OpenAPS.FreeAPS.tempTargetsPresets, as: [TempTarget].self)?.reversed() ?? []
    }
}

private extension TempTarget {
    var isActive: Bool {
        let expirationTime = createdAt.addingTimeInterval(Int(duration).minutes.timeInterval)
        return expirationTime > Date() && createdAt <= Date()
    }

    var isWithinLastDay: Bool {
        createdAt.addingTimeInterval(1.days.timeInterval) > Date()
    }
}
