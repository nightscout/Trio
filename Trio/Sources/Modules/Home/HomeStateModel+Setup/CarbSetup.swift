import CoreData
import Foundation

extension Home.StateModel {
    // MARK: - Carbs

    @MainActor func setupCarbsController() {
        carbsControllerDelegate.onContentChange = { [weak self] in
            Task { @MainActor in
                self?.updateCarbsFromController()
            }
        }

        do {
            try carbsController.performFetch()
            updateCarbsFromController()
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) Failed to perform carbs fetch: \(error)")
        }
    }

    @MainActor func updateCarbsFromController() {
        guard let objects = carbsController.fetchedObjects else { return }
        carbsFromPersistence = objects
    }

    // MARK: - FPUs

    @MainActor func setupFPUController() {
        fpuControllerDelegate.onContentChange = { [weak self] in
            Task { @MainActor in
                self?.updateFPUsFromController()
            }
        }

        do {
            try fpuController.performFetch()
            updateFPUsFromController()
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) Failed to perform FPU fetch: \(error)")
        }
    }

    @MainActor func updateFPUsFromController() {
        guard let objects = fpuController.fetchedObjects else { return }
        fpusFromPersistence = objects
    }
}
