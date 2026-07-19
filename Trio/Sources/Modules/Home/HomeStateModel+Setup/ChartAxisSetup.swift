import CoreData
import Foundation

extension Home.StateModel {
    /// Recomputes the main glucose chart Y axis bounds from the fetched glucose objects.
    /// Runs on the main actor since the inputs are viewContext managed objects.
    @MainActor func updateGlucoseChartYAxis(glucoseValues: [GlucoseStored]) {
        let glucoseMapped = glucoseValues.map { Decimal($0.glucose) }
        let forecastValues = preprocessedData.map { Decimal($0.forecastValue.value) }

        // Ensure all values exist, otherwise set default values
        guard let minGlucose = glucoseMapped.min(), let maxGlucose = glucoseMapped.max() else {
            minYAxisValue = 39
            maxYAxisValue = 200
            return
        }

        let minForecast = forecastValues.min()
        let maxForecast = forecastValues.max()

        // Adjust max forecast to be no more than 50 over max glucose
        let adjustedMaxForecast = min(maxForecast ?? maxGlucose + 50, maxGlucose + 50)
        let minOverall = min(minGlucose, minForecast ?? minGlucose)
        let maxOverall = max(maxGlucose, adjustedMaxForecast)

        var maxYValue: Decimal = 200
        if maxOverall > 200, maxOverall <= 225 {
            maxYValue = 250
        } else if maxOverall > 225, maxOverall <= 275 {
            maxYValue = 300
        } else if maxOverall > 275, maxOverall <= 325 {
            maxYValue = 350
        } else if maxOverall > 325 {
            maxYValue = 400
        }

        minYAxisValue = minOverall
        maxYAxisValue = maxYValue
    }

    /// Recomputes the COB chart Y axis bounds from the fetched determination objects.
    @MainActor func yAxisChartDataCobChart(determinations: [OrefDetermination]) {
        let cobMapped = determinations.map { Decimal($0.cob) }

        if let maxCob = cobMapped.max() {
            minValueCobChart = 0
            maxValueCobChart = maxCob == 0 ? 20 : maxCob + 20
        } else {
            minValueCobChart = 0
            maxValueCobChart = 20
        }
    }

    /// Recomputes the IOB chart Y axis bounds from the fetched determination objects.
    @MainActor func yAxisChartDataIobChart(determinations: [OrefDetermination]) {
        let iobMapped = determinations.compactMap { $0.iob?.decimalValue }

        if let minIob = iobMapped.min(), let maxIob = iobMapped.max() {
            minValueIobChart = minIob
            maxValueIobChart = maxIob
        } else {
            minValueIobChart = 0
            maxValueIobChart = 5
        }
    }
}
