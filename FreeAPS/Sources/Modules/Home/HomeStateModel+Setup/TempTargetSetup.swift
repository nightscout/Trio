import CoreData
import Foundation

extension Home.StateModel {
    func setupTempTargetsStored() {
        Task {
            let ids = await self.fetchTempTargets()
            let tempTargetObjects: [TempTargetStored] = await CoreDataStack.shared
                .getNSManagedObject(with: ids, context: viewContext)
            await updateTempTargetsArray(with: tempTargetObjects)
        }
    }

    private func fetchTempTargets() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TempTargetStored.self,
            onContext: tempTargetFetchContext,
            predicate: NSPredicate.lastActiveTempTarget,
            key: "date",
            ascending: false
        )

        return await tempTargetFetchContext.perform {
            guard let fetchedResults = results as? [TempTargetStored] else { return [] }
            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateTempTargetsArray(with objects: [TempTargetStored]) {
        tempTargetStored = objects
    }

    // Setup expired TempTargets
    func setupTempTargetsRunStored() {
        Task {
            let ids = await self.fetchTempTargetRunStored()
            let tempTargetRunObjects: [TempTargetRunStored] = await CoreDataStack.shared
                .getNSManagedObject(with: ids, context: viewContext)
            await updateTempTargetRunStoredArray(with: tempTargetRunObjects)
        }
    }

    private func fetchTempTargetRunStored() async -> [NSManagedObjectID] {
        let predicate = NSPredicate(format: "startDate >= %@", Date.oneDayAgo as NSDate)
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TempTargetRunStored.self,
            onContext: tempTargetFetchContext,
            predicate: predicate,
            key: "startDate",
            ascending: false
        )

        return await tempTargetFetchContext.perform {
            guard let fetchedResults = results as? [TempTargetRunStored] else { return [] }
            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateTempTargetRunStoredArray(with objects: [TempTargetRunStored]) {
        tempTargetRunStored = objects
    }

    @MainActor func saveToTempTargetRunStored(withID id: NSManagedObjectID) async {
        await viewContext.perform {
            do {
                guard let object = try self.viewContext.existingObject(with: id) as? TempTargetStored else { return }

                let newTempTargetRunStored = TempTargetRunStored(context: self.viewContext)
                newTempTargetRunStored.id = UUID()
                newTempTargetRunStored.name = object.name
                newTempTargetRunStored.startDate = object.date ?? .distantPast
                newTempTargetRunStored.endDate = Date()
                newTempTargetRunStored.target = object.target ?? 0
                newTempTargetRunStored.tempTarget = object
                newTempTargetRunStored.isUploadedToNS = false

            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to initialize a new Override Run Object"
                )
            }
        }
    }

    @MainActor func cancelTempTarget(withID id: NSManagedObjectID) async {
        do {
            let profileToCancel = try viewContext.existingObject(with: id) as? TempTargetStored
            profileToCancel?.enabled = false

            await saveToTempTargetRunStored(withID: id)

            guard viewContext.hasChanges else { return }
            try viewContext.save()

            // We also need to update the storage for temp targets
            tempTargetStorage.saveTempTargetsToStorage([TempTarget.cancel(at: Date())])

            Foundation.NotificationCenter.default.post(name: .didUpdateTempTargetConfiguration, object: nil)
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to cancel Profile")
        }
    }

    func computeAdjustedPercentage(halfBasalTargetValue: Decimal, tempTargetValue: Decimal) -> Int {
        let normalTarget: Decimal = 100
        let deviationFromNormal = halfBasalTargetValue - normalTarget

        let adjustmentFactor = deviationFromNormal + (tempTargetValue - normalTarget)
        let adjustmentRatio: Decimal = (deviationFromNormal * adjustmentFactor <= 0) ? maxValue : deviationFromNormal /
            adjustmentFactor

        return Int(Double(min(adjustmentRatio, maxValue) * 100).rounded())
    }
}
