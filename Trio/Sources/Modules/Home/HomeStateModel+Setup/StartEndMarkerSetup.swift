import Foundation

extension Home.StateModel {
    // Update start and  end marker to fix scroll update problem with x axis
    func updateStartEndMarkers() {
        startMarker = Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970 - 86400))

        let threeHourSinceNow = Date(timeIntervalSinceNow: TimeInterval(hours: 3))

        // min is 1.5h -> (1.5*1h = 1.5*(5*12*60))
        let dynamicFutureDateForCone = Date(timeIntervalSinceNow: TimeInterval(
            Int(1.5) * 5 * minCount * 60
        ))

        endMarker = forecastDisplayType == .lines ? threeHourSinceNow : dynamicFutureDateForCone <= threeHourSinceNow ?
            dynamicFutureDateForCone.addingTimeInterval(TimeInterval(minutes: 30)) : threeHourSinceNow
    }
}
