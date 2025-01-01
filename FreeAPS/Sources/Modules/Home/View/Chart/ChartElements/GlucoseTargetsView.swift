import Charts
import Foundation
import SwiftUI

struct GlucoseTargetsView: ChartContent {
    let startMarker: Date
    let endMarker: Date
    let units: GlucoseUnits
    let bgTargets: BGTargets

    var body: some ChartContent {
        drawGlucoseTargets()
    }

    /**
     Draws glucose target ranges on the chart

     - Returns: A ChartContent containing line marks representing target glucose ranges

     The function:
     - Creates target profiles for two consecutive days
     - Converts values between mg/dL and mmol/L based on user settings
     - Draws green lines to visualize the target ranges
     */
    private func drawGlucoseTargets() -> some ChartContent {
        // Array to store target profiles for visualization
        var targetProfiles: [TargetProfile] = []
        let targets = bgTargets.targets

        // Generate profiles for today and tomorrow, because otherwise the targets would be cut off at midnight
        // TODO: maybe theres a better solution than introducing a second for loop?
        let days = [0, 1]

        for dayOffset in days {
            // Calculate base date for current day offset
            // it should be the start of the day of the startMarker
            let baseDate = Calendar.current.startOfDay(for: startMarker)
                .addingTimeInterval(TimeInterval(dayOffset * 24 * 60 * 60))

            for (index, target) in targets.enumerated() {
                // Calculate start time by adding target offset
                let startTime = baseDate.addingTimeInterval(TimeInterval(target.offset * 60))

                // Calculate end time - either next target or end of day
                let endTime: Date = {
                    if index + 1 < targets.count {
                        return baseDate.addingTimeInterval(TimeInterval(targets[index + 1].offset * 60))
                    } else {
                        return baseDate.addingTimeInterval(24 * 60 * 60)
                    }
                }()

                // append target profile to array
                targetProfiles.append(
                    TargetProfile(
                        value: units == .mgdL ? target.low : target.low.asMmolL,
                        startTime: startTime.timeIntervalSinceReferenceDate,
                        endTime: endTime.timeIntervalSinceReferenceDate
                    )
                )
            }
        }

        // Draw target lines for each profile
        return ForEach(targetProfiles, id: \.self) { profile in
            LineMark(
                x: .value("Time", Date(timeIntervalSinceReferenceDate: profile.startTime)),
                y: .value("Target", profile.value)
            )
            .lineStyle(.init(lineWidth: 0.5))
            .foregroundStyle(Color.green.opacity(0.8))

            LineMark(
                x: .value("Time", Date(timeIntervalSinceReferenceDate: profile.endTime)),
                y: .value("Target", profile.value)
            )
            .lineStyle(.init(lineWidth: 0.5))
            .foregroundStyle(Color.green.opacity(0.8))
        }
    }
}

struct TargetProfile: Hashable {
    let value: Decimal
    let startTime: TimeInterval
    let endTime: TimeInterval
}

private extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
}
