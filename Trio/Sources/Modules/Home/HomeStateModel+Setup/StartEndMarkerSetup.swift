import Foundation

extension Home.StateModel {
    /// Leading edge of the chart-feeding fetch window (chart-only; dosing
    /// reads its own storage fetches).
    var chartHistoryStartDate: Date {
        Date(timeIntervalSinceNow: -MainChartHelper.Config.chartHistorySeconds)
    }

    // Update start and  end marker to fix scroll update problem with x axis
    func updateStartEndMarkers() {
        startMarker = Date(timeIntervalSinceNow: -MainChartHelper.Config.chartHistorySeconds)

        let threeHourSinceNow = Date(timeIntervalSinceNow: TimeInterval(hours: 3))

        // min is 1.5h -> (1.5*1h = 1.5*(5*12*60))
        let dynamicFutureDateForCone = Date(timeIntervalSinceNow: TimeInterval(
            Int(1.5) * 5 * minCount * 60
        ))

        endMarker = forecastDisplayType == .lines ? threeHourSinceNow : dynamicFutureDateForCone <= threeHourSinceNow ?
            dynamicFutureDateForCone.addingTimeInterval(TimeInterval(minutes: 30)) : threeHourSinceNow
    }
}
