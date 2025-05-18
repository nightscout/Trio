import CoreData
import Foundation

extension Home.StateModel {
    // Asynchronously preprocess Forecast data in a background thread
    func preprocessForecastData() async -> [(
        id: UUID, forecastID: NSManagedObjectID, forecastValueIDs: [NSManagedObjectID]
    )] {
        do {
            // Get the Determination ID on the main context
            guard let determination = await viewContext.perform({
                self.enactedAndNonEnactedDeterminations.first
            }) else {
                debug(.default, "No determination found for forecast preprocessing")
                return []
            }

            // Fetch complete forecast hierarchy with prefetched values
            return try await determinationStorage.fetchForecastHierarchy(
                for: determination.objectID,
                in: taskContext
            )
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to preprocess forecast data: \(error)"
            )
            return []
        }
    }

    // Update forecast data and UI on the main thread
    @MainActor func updateForecastData() async {
        let forecastDataIDs = await preprocessForecastData()

        var allForecastValues = [[Int]]()
        var preprocessedData = [(id: UUID, forecast: Forecast, forecastValue: ForecastValue)]()

        // Process prefetched data directly
        for data in forecastDataIDs {
            if let forecast = try? viewContext.existingObject(with: data.forecastID) as? Forecast {
                let values = data.forecastValueIDs.compactMap {
                    try? viewContext.existingObject(with: $0) as? ForecastValue
                }

                // Extract values for graph
                let forecastValueInts = values.map { Int($0.value) }
                allForecastValues.append(forecastValueInts)

                // Add data for further processing
                preprocessedData.append(contentsOf: values.map {
                    (id: data.id, forecast: forecast, forecastValue: $0)
                })
            }
        }

        // Update UI-relevant data
        self.preprocessedData = preprocessedData

        guard !allForecastValues.isEmpty else {
            minForecast = []
            maxForecast = []
            return
        }

        minCount = max(12, allForecastValues.map(\.count).min() ?? 0)
        let localMinCount = minCount

        guard localMinCount > 0 else { return }

        // Calculate min/max values for graph
        let (minResult, maxResult) = await Task.detached {
            let minForecast = (0 ..< localMinCount).map { index in
                allForecastValues.compactMap { $0.indices.contains(index) ? $0[index] : nil }
                    .min() ?? 0
            }

            let maxForecast = (0 ..< localMinCount).map { index in
                allForecastValues.compactMap { $0.indices.contains(index) ? $0[index] : nil }
                    .max() ?? 0
            }

            return (minForecast, maxForecast)
        }.value

        minForecast = minResult
        maxForecast = maxResult
    }
}
