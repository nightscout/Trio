import CoreData
import Foundation

extension Home.StateModel {
    // Asynchronously preprocess Forecast data in a background thread
    func preprocessForecastData() async -> [(id: UUID, forecastID: NSManagedObjectID, forecastValueIDs: [NSManagedObjectID])] {
        // Get the Determination ID on the main context
        guard let id = await viewContext.perform({ self.enactedAndNonEnactedDeterminations.first?.objectID }) else {
            return []
        }

        // Get the Forecast IDs for the Determination ID
        // Here we can safely use a background context since we are using the NSManagedObjectID
        let forecastIDs = await determinationStorage.getForecastIDs(for: id, in: taskContext)

        var result: [(id: UUID, forecastID: NSManagedObjectID, forecastValueIDs: [NSManagedObjectID])] = []

        // Use a task group to fetch Forecast VALUE IDs concurrently
        await withTaskGroup(of: (UUID, NSManagedObjectID, [NSManagedObjectID]).self) { group in
            for forecastID in forecastIDs {
                group.addTask {
                    // Fetch forecast value IDs asynchronously (but outside of perform)
                    let forecastValueIDs = await self.determinationStorage.getForecastValueIDs(
                        for: forecastID,
                        in: self.taskContext
                    )
                    return (UUID(), forecastID, forecastValueIDs)
                }
            }

            // Collect the results from the task group
            for await (uuid, forecastID, forecastValueIDs) in group {
                result.append((id: uuid, forecastID: forecastID, forecastValueIDs: forecastValueIDs))
            }
        }

        return result
    }

    // Update forecast data and UI on the main thread
    @MainActor func updateForecastData() async {
        // Preprocess forecast data on a background thread
        let forecastDataIDs = await preprocessForecastData()

        // Use an Array of Int instead of ForecastValues to be able to pass values thread safe
        var allForecastValues = [[Int]]()
        var preprocessedData = [(id: UUID, forecast: Forecast, forecastValue: ForecastValue)]()

        // Use a task group to fetch forecast values concurrently
        await withTaskGroup(of: (UUID, Forecast?, [ForecastValue]).self) { group in
            for data in forecastDataIDs {
                group.addTask {
                    await self.determinationStorage
                        .fetchForecastObjects(
                            for: data,
                            in: self.viewContext
                        ) // This directly returns NSManagedobjects on the Main Thread
                }
            }

            // Collect the results from the task group
            for await (id, forecast, forecastValues) in group {
                guard let forecast = forecast, !forecastValues.isEmpty else { continue }

                // Extract only the 'value' from ForecastValue on the main thread
                let forecastValueInts = forecastValues
                    .compactMap { Int($0.value) }
                allForecastValues.append(forecastValueInts)
                preprocessedData.append(contentsOf: forecastValues.map { (id: id, forecast: forecast, forecastValue: $0) })
            }
        }

        // Update Array on the Main Thread
        self.preprocessedData = preprocessedData

        // Ensure there are forecast values to process
        guard !allForecastValues.isEmpty else {
            minForecast = []
            maxForecast = []
            return
        }

        minCount = max(12, allForecastValues.map(\.count).min() ?? 0)
        guard minCount > 0 else { return }

        // Copy allForecastValues to a local constant for thread safety
        let localAllForecastValues = allForecastValues

        // Calculate min and max forecast values in a background task
        let (minResult, maxResult) = await Task.detached {
            let minForecast = (0 ..< self.minCount).map { index in
                localAllForecastValues.compactMap { $0.indices.contains(index) ? $0[index] : nil }.min() ?? 0
            }

            let maxForecast = (0 ..< self.minCount).map { index in
                localAllForecastValues.compactMap { $0.indices.contains(index) ? $0[index] : nil }.max() ?? 0
            }

            return (minForecast, maxForecast)
        }.value

        // Update the properties on the main thread
        minForecast = minResult
        maxForecast = maxResult
    }
}
