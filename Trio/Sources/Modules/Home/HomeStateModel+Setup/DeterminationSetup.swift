import CoreData
import Foundation

extension Home.StateModel {
    // MARK: - Enacted Determination

    @MainActor func setupEnactedDeterminationController() {
        enactedDeterminationControllerDelegate.onContentChange = { [weak self] in
            Task { @MainActor in
                self?.scheduleForecastUpdate()
            }
        }

        do {
            try enactedDeterminationController.performFetch()
            updateEnactedDeterminationFromController()
            // Initial population; assigned to `forecastUpdateTask` so a change arriving
            // during startup cancels it instead of racing it.
            forecastUpdateTask = Task { @MainActor in
                await self.updateForecastData()
            }
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) Failed to perform enacted determination fetch: \(error)")
        }
    }

    /// Coalesces rapid determination changes — each cancels the previous pending recompute.
    @MainActor func scheduleForecastUpdate() {
        forecastUpdateTask?.cancel()
        forecastUpdateTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            updateEnactedDeterminationFromController()
            await updateForecastData()
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
