import CoreData
import Foundation

extension Home.StateModel {
    func setupTempTargetsStored() {
        Task {
            do {
                let ids = try await self.fetchTempTargets()
                let tempTargetObjects: [TempTargetStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: ids, context: viewContext)
                await updateTempTargetsArray(with: tempTargetObjects)
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Error setting up tempTargetStored: \(error)"
                )
            }
        }
    }

    private func fetchTempTargets() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TempTargetStored.self,
            onContext: tempTargetFetchContext,
            predicate: NSPredicate.tempTargetsForMainChart,
            key: "date",
            ascending: false
        )

        return try await tempTargetFetchContext.perform {
            guard let fetchedResults = results as? [TempTargetStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateTempTargetsArray(with objects: [TempTargetStored]) {
        tempTargetStored = objects
    }

    // Setup expired TempTargets
    func setupTempTargetsRunStored() {
        Task {
            do {
                let ids = try await self.fetchTempTargetRunStored()
                let tempTargetRunObjects: [TempTargetRunStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: ids, context: viewContext)
                await updateTempTargetRunStoredArray(with: tempTargetRunObjects)
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Error setting up temp targetsRunStored: \(error)"
                )
            }
        }
    }

    private func fetchTempTargetRunStored() async throws -> [NSManagedObjectID] {
        let predicate = NSPredicate(format: "startDate >= %@", Date.oneDayAgo as NSDate)
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TempTargetRunStored.self,
            onContext: tempTargetFetchContext,
            predicate: predicate,
            key: "startDate",
            ascending: false
        )

        return try await tempTargetFetchContext.perform {
            guard let fetchedResults = results as? [TempTargetRunStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateTempTargetRunStoredArray(with objects: [TempTargetRunStored]) {
        tempTargetRunStored = objects
    }

    @MainActor func cancelTempTarget(withID id: NSManagedObjectID) async {
        do {
            guard let profileToCancel = try viewContext.existingObject(with: id) as? TempTargetStored else { return }

            profileToCancel.enabled = false

            guard viewContext.hasChanges else { return }
            try viewContext.save()

            // Do not save Cancel-Temp Targets from Nightscout to RunStoredEntity
            if profileToCancel.duration != 0, profileToCancel.target != 0 {
                await saveToTempTargetRunStored(object: profileToCancel)
            }

            // We also need to update the storage for temp targets
            tempTargetStorage.saveTempTargetsToStorage([TempTarget.cancel(at: Date())])

            Foundation.NotificationCenter.default.post(name: .didUpdateTempTargetConfiguration, object: nil)
        } catch let error as NSError {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to cancel Temp Target with error: \(error)")
        }
    }

    @MainActor func saveToTempTargetRunStored(object: TempTargetStored) async {
        let newTempTargetRunStored = TempTargetRunStored(context: viewContext)
        newTempTargetRunStored.id = UUID()
        newTempTargetRunStored.name = object.name
        newTempTargetRunStored.startDate = object.date ?? .distantPast
        newTempTargetRunStored.endDate = Date()
        newTempTargetRunStored.target = object.target ?? 0
        newTempTargetRunStored.tempTarget = object
        newTempTargetRunStored.isUploadedToNS = false

        do {
            guard viewContext.hasChanges else { return }
            try viewContext.save()
        } catch let error as NSError {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save Temp Target with error: \(error)")
        }
    }

    func computeAdjustedPercentage(halfBasalTargetValue: Decimal, tempTargetValue: Decimal) -> Int {
        let normalTarget: Decimal = 100
        let deviationFromNormal = halfBasalTargetValue - normalTarget

        let adjustmentFactor = deviationFromNormal + (tempTargetValue - normalTarget)
        let adjustmentRatio: Decimal = (deviationFromNormal * adjustmentFactor <= 0) ? autosensMax : deviationFromNormal /
            adjustmentFactor

        return Int(Double(min(adjustmentRatio, autosensMax) * 100).rounded())
    }
}
