import CoreData
import Foundation

extension Home.StateModel {
    // MARK: - Enacted Determination

    @MainActor func setupEnactedDeterminationController() {
        enactedDeterminationControllerDelegate.onContentChange = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateEnactedDeterminationFromController()
                await self.updateForecastData()
            }
        }

        do {
            try enactedDeterminationController.performFetch()
            updateEnactedDeterminationFromController()
            Task { @MainActor in
                await self.updateForecastData()
            }
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) Failed to perform enacted determination fetch: \(error)")
        }
    }

    @MainActor private func updateEnactedDeterminationFromController() {
        guard let objects = enactedDeterminationController.fetchedObjects else { return }
        determinationsFromPersistence = objects
    }

    // MARK: - Determinations for COB/IOB Charts

    @MainActor func setupDeterminationController() {
        determinationControllerDelegate.onContentChange = { [weak self] in
            Task { @MainActor in
                self?.updateDeterminationsFromController()
            }
        }

        do {
            try determinationController.performFetch()
            updateDeterminationsFromController()
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) Failed to perform determination fetch: \(error)")
        }
    }

    @MainActor func updateDeterminationsFromController() {
        guard let objects = determinationController.fetchedObjects else { return }
        enactedAndNonEnactedDeterminations = objects
        yAxisChartDataCobChart(determinations: objects)
        yAxisChartDataIobChart(determinations: objects)
    }
}
