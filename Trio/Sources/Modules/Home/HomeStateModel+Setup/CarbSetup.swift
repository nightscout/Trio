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
            warning(.ui, "Fetching carbs for home screen failed", error: error)
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
            warning(.ui, "Fetching fat and protein entries for home screen failed", error: error)
        }
    }

    @MainActor func updateFPUsFromController() {
        guard let objects = fpuController.fetchedObjects else { return }
        fpusFromPersistence = objects
    }
}
