import CoreData
import Foundation

extension Home.StateModel {
    // MARK: - Temp Targets

    @MainActor func setupTempTargetController() {
        tempTargetControllerDelegate.onContentChange = { [weak self] in
            Task { @MainActor in
                self?.updateTempTargetsFromController()
            }
        }

        do {
            try tempTargetController.performFetch()
            updateTempTargetsFromController()
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) Failed to perform temp target fetch: \(error)")
        }
    }

    @MainActor func updateTempTargetsFromController() {
        guard let objects = tempTargetController.fetchedObjects else { return }
        tempTargetStored = objects
    }

    // MARK: - Temp Target Runs

    @MainActor func setupTempTargetRunController() {
        tempTargetRunControllerDelegate.onContentChange = { [weak self] in
            Task { @MainActor in
                self?.updateTempTargetRunsFromController()
            }
        }

        do {
            try tempTargetRunController.performFetch()
            updateTempTargetRunsFromController()
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) Failed to perform temp target run fetch: \(error)")
        }
    }

    @MainActor func updateTempTargetRunsFromController() {
        guard let objects = tempTargetRunController.fetchedObjects else { return }
        tempTargetRunStored = objects
    }

    // MARK: - Temp Target Actions

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
}
