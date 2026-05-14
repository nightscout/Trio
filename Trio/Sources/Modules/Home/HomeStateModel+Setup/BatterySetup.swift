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
            debug(.default, "\(DebuggingIdentifiers.failed) Failed to perform battery fetch: \(error)")
        }
    }

    @MainActor private func updateBatteryFromController() {
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
