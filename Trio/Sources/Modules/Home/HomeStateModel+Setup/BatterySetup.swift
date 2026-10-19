import CoreData
import Foundation

extension Home.StateModel {
    @MainActor func setupBatteryController() {
        batteryControllerDelegate.onContentChange = { [weak self] in
            Task { @MainActor in
                self?.updateBatteryFromController()
            }
        }

        do {
            try batteryController.performFetch()
            updateBatteryFromController()
        } catch {
            warning(.ui, "Fetching pump battery for home screen failed", error: error)
        }
    }

    @MainActor func updateBatteryFromController() {
        guard let objects = batteryController.fetchedObjects else { return }
        batteryFromPersistence = objects
    }

    /// Called from the `pumpDisplayState` sink, `settingsDidChange` and `pumpSettingsDidChange`.
    func setupBatteryArray() {
        Task { @MainActor in
            updateBatteryFromController()
        }
    }
}
