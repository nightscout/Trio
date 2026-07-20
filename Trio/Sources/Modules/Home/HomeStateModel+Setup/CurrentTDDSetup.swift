import CoreData
import Foundation

extension Home.StateModel {
    @MainActor func setupTDDController() {
        tddControllerDelegate.onContentChange = { [weak self] in
            Task { @MainActor in
                self?.updateTDDFromController()
            }
        }

        do {
            try tddController.performFetch()
            updateTDDFromController()
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) Failed to perform TDD fetch: \(error)")
        }
    }

    @MainActor private func updateTDDFromController() {
        guard let objects = tddController.fetchedObjects else { return }
        fetchedTDDs = objects.map { TDD(totalDailyDose: $0.total?.decimalValue, timestamp: $0.date) }
    }
}
