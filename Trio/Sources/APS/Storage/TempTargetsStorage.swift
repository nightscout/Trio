import CoreData
import Foundation
import SwiftDate
import Swinject

protocol TempTargetsObserver {
    func tempTargetsDidUpdate(_ targets: [TempTarget])
}

protocol TempTargetsStorage {
    func storeTempTarget(tempTarget: TempTarget) async throws
    func saveTempTargetsToStorage(_ targets: [TempTarget])
    func fetchForTempTargetPresets() async throws -> [NSManagedObjectID]
    func fetchScheduledTempTargets() async throws -> [NSManagedObjectID]
    func fetchScheduledTempTarget(for targetDate: Date) async throws -> [NSManagedObjectID]
    func copyRunningTempTarget(_ tempTarget: TempTargetStored) async -> NSManagedObjectID
    func deleteTempTargetPreset(_ objectID: NSManagedObjectID) async
    func loadLatestTempTargetConfigurations(fetchLimit: Int) async throws -> [NSManagedObjectID]
    func syncDate() -> Date
    func recent() -> [TempTarget]
    func getTempTargetsNotYetUploadedToNightscout() async throws -> [NightscoutTreatment]
    func getTempTargetRunsNotYetUploadedToNightscout() async throws -> [NightscoutTreatment]
    func presets() -> [TempTarget]
    func current() -> TempTarget?
    func existsTempTarget(with date: Date) async -> Bool
}

final class BaseTempTargetsStorage: TempTargetsStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseTempTargetsStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settingsManager: SettingsManager!

    private let viewContext = CoreDataStack.shared.persistentContainer.viewContext

    private let context: NSManagedObjectContext

    init(resolver: Resolver, context: NSManagedObjectContext? = nil) {
        self.context = context ?? CoreDataStack.shared.newTaskContext()
        injectServices(resolver)
    }

    func loadLatestTempTargetConfigurations(fetchLimit: Int) async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TempTargetStored.self,
            onContext: context,
            predicate: NSPredicate.lastActiveTempTarget,
            key: "orderPosition",
            ascending: true,
            fetchLimit: fetchLimit
        )

        return try await context.perform {
            guard let fetchedResults = results as? [TempTargetStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map(\.objectID)
        }
    }

    /// Returns the NSManagedObjectID of the Temp Target Presets
    func fetchForTempTargetPresets() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TempTargetStored.self,
            onContext: context,
            predicate: NSPredicate.allTempTargetPresets,
            key: "orderPosition",
            ascending: true
        )

        return try await context.perform {
            guard let fetchedResults = results as? [TempTargetStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map(\.objectID)
        }
    }

    func fetchScheduledTempTargets() async throws -> [NSManagedObjectID] {
        let scheduledTempTargets = NSPredicate(format: "date > %@", Date() as NSDate)

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TempTargetStored.self,
            onContext: context,
            predicate: scheduledTempTargets,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedResults = results as? [TempTargetStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map(\.objectID)
        }
    }

    func fetchScheduledTempTarget(for targetDate: Date) async throws -> [NSManagedObjectID] {
        let predicate = NSPredicate(format: "date == %@", targetDate as NSDate)

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TempTargetStored.self,
            onContext: context,
            predicate: predicate,
            key: "date",
            ascending: false,
            fetchLimit: 1
        )

        return try await context.perform {
            guard let fetchedResults = results as? [TempTargetStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map(\.objectID)
        }
    }

    func storeTempTarget(tempTarget: TempTarget) async throws {
        var presetCount = -1
        if tempTarget.isPreset == true {
            let presets = try await fetchForTempTargetPresets()
            presetCount = presets.count
        }

        try await context.perform {
            let newTempTarget = TempTargetStored(context: self.context)
            newTempTarget.date = tempTarget.createdAt
            newTempTarget.id = UUID()
            newTempTarget.enabled = tempTarget.enabled ?? false
            newTempTarget.duration = tempTarget.duration as NSDecimalNumber
            newTempTarget.isUploadedToNS = false
            newTempTarget.name = tempTarget.name
            newTempTarget.target = NSDecimalNumber(decimal: tempTarget.targetTop ?? 0)
            newTempTarget.isPreset = tempTarget.isPreset ?? false

            // Nullify half basal target to ensure the latest HBT is used via OpenAPS Manager when sending TT data to oref
            newTempTarget.halfBasalTarget = nil

            if let halfBasalTarget = tempTarget.halfBasalTarget,
               halfBasalTarget != self.settingsManager.preferences.halfBasalExerciseTarget
            {
                newTempTarget.halfBasalTarget = NSDecimalNumber(decimal: halfBasalTarget)
            }

            if tempTarget.isPreset == true, presetCount > -1 {
                newTempTarget.orderPosition = Int16(presetCount + 1)
            }

            do {
                guard self.context.hasChanges else { return }
                try self.context.save()
            } catch let error as NSError {
                debug(.default, "\(DebuggingIdentifiers.failed) Failed to save new temp target with error: \(error.userInfo)")
                throw error
            }
        }
    }

    func saveTempTargetsToStorage(_ targets: [TempTarget]) {
        processQueue.async {
            let file = OpenAPS.Settings.tempTargets
            var uniqEvents: [TempTarget] = []
            self.storage.transaction { storage in
                storage.append(targets, to: file, uniqBy: \.createdAt)

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

    func existsTempTarget(with date: Date) async -> Bool {
        await context.perform {
            // Fetch all Temp Targets with the given date
            let fetchRequest: NSFetchRequest<TempTargetStored> = TempTargetStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "date == %@", date as NSDate)

            do {
                let results = try self.context.fetch(fetchRequest)
                return !results.isEmpty
            } catch let error as NSError {
                debugPrint("\(DebuggingIdentifiers.failed) Failed to check for existing Temp Target: \(error)")
                return false
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
        newTempTarget.halfBasalTarget = tempTarget.halfBasalTarget != 160 ? tempTarget.halfBasalTarget : nil

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

    func deleteTempTargetPreset(_ objectID: NSManagedObjectID) async {
        let taskContext = context != CoreDataStack.shared.newTaskContext()
            ? context
            : CoreDataStack.shared.newTaskContext()

        await taskContext.perform {
            do {
                let result = try taskContext.existingObject(with: objectID) as? TempTargetStored
                guard let tempTarget = result else {
                    debug(.default, "\(DebuggingIdentifiers.failed) Temp Target for batch delete not found.")
                    return
                }

                taskContext.delete(tempTarget)

                guard taskContext.hasChanges else { return }
                try taskContext.save()
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) Failed to delete Temp Target: \(error)")
            }
        }
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

    func getTempTargetsNotYetUploadedToNightscout() async throws -> [NightscoutTreatment] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TempTargetStored.self,
            onContext: context,
            predicate: NSPredicate.lastActiveAdjustmentNotYetUploadedToNightscout,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedTempTargets = results as? [TempTargetStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedTempTargets.map { tempTarget in
                NightscoutTreatment(
                    duration: Int(truncating: tempTarget.duration ?? 60),
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsTempTarget,
                    createdAt: tempTarget.date ?? Date(),
                    enteredBy: TempTarget.local,
                    bolus: nil,
                    insulin: nil,
                    notes: tempTarget.name ?? TempTarget.custom,
                    carbs: nil,
                    targetTop: tempTarget
                        .target as Decimal? ?? (self.settingsManager.settings.units == .mgdL ? 100.0 : 100.asMmolL),
                    targetBottom: tempTarget
                        .target as Decimal? ?? (self.settingsManager.settings.units == .mgdL ? 100.0 : 100.asMmolL)
                )
            }
        }
    }

    func getTempTargetRunsNotYetUploadedToNightscout() async throws -> [NightscoutTreatment] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TempTargetRunStored.self,
            onContext: context,
            predicate: NSPredicate(
                format: "startDate >= %@ AND isUploadedToNS == %@",
                Date.oneDayAgo as NSDate,
                false as NSNumber
            ),
            key: "startDate",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedTempTargetRuns = results as? [TempTargetRunStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedTempTargetRuns.map { tempTargetRun in
                var durationInMinutes = (tempTargetRun.endDate?.timeIntervalSince(tempTargetRun.startDate ?? Date()) ?? 1) / 60
                durationInMinutes = durationInMinutes < 1 ? 1 : durationInMinutes
                return NightscoutTreatment(
                    duration: Int(durationInMinutes),
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsTempTarget,
                    createdAt: (tempTargetRun.startDate ?? tempTargetRun.tempTarget?.date) ?? Date(),
                    enteredBy: TempTarget.local,
                    bolus: nil,
                    insulin: nil,
                    notes: tempTargetRun.tempTarget?.name ?? TempTarget.custom,
                    carbs: nil,
                    targetTop: tempTargetRun
                        .target as Decimal? ?? (self.settingsManager.settings.units == .mgdL ? 100.0 : 100.asMmolL),
                    targetBottom: tempTargetRun
                        .target as Decimal? ?? (self.settingsManager.settings.units == .mgdL ? 100.0 : 100.asMmolL)
                )
            }
        }
    }

    func presets() -> [TempTarget] {
        storage.retrieve(OpenAPS.Trio.tempTargetsPresets, as: [TempTarget].self)?.reversed() ?? []
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
