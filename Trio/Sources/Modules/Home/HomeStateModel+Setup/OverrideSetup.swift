import CoreData
import Foundation

extension Home.StateModel {
    // MARK: - Overrides

    @MainActor func setupOverrideController() {
        overrideControllerDelegate.onContentChange = { [weak self] in
            Task { @MainActor in
                self?.updateOverridesFromController()
            }
        }

        do {
            try overrideController.performFetch()
            updateOverridesFromController()
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) Failed to perform override fetch: \(error)")
        }
    }

    @MainActor private func updateOverridesFromController() {
        guard let objects = overrideController.fetchedObjects else { return }
        overrides = objects
    }

    // MARK: - Override Runs

    @MainActor func setupOverrideRunController() {
        overrideRunControllerDelegate.onContentChange = { [weak self] in
            Task { @MainActor in
                self?.updateOverrideRunsFromController()
            }
        }

        do {
            try overrideRunController.performFetch()
            updateOverrideRunsFromController()
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) Failed to perform override run fetch: \(error)")
        }
    }

    @MainActor func updateOverrideRunsFromController() {
        guard let objects = overrideRunController.fetchedObjects else { return }
        overrideRunStored = objects
    }

    // MARK: - Override Actions

    /// Cancels the running Override, creates an entry in the OverrideRunStored Core Data entity and posts a custom notification so that the AdjustmentsView gets updated
    @MainActor func cancelOverride(withID id: NSManagedObjectID) async {
        do {
            guard let profileToCancel = try viewContext.existingObject(with: id) as? OverrideStored else { return }

            profileToCancel.enabled = false

            guard viewContext.hasChanges else { return }
            try viewContext.save()

            await saveToOverrideRunStored(object: profileToCancel)

            Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
        } catch let error as NSError {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to cancel Profile with error: \(error)")
        }
    }

    /// We can safely pass the NSManagedObject  as we are doing everything on the Main Actor
    @MainActor func saveToOverrideRunStored(object: OverrideStored) async {
        let newOverrideRunStored = OverrideRunStored(context: viewContext)
        newOverrideRunStored.id = UUID()
        newOverrideRunStored.name = object.name
        newOverrideRunStored.startDate = object.date ?? .distantPast
        newOverrideRunStored.endDate = Date()
        newOverrideRunStored.target = NSDecimalNumber(decimal: overrideStorage.calculateTarget(override: object))
        newOverrideRunStored.override = object
        newOverrideRunStored.isUploadedToNS = false

        do {
            guard viewContext.hasChanges else { return }
            try viewContext.save()
        } catch let error as NSError {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save an Override to the OverrideRunStored entity with error: \(error)"
            )
        }
    }
}
