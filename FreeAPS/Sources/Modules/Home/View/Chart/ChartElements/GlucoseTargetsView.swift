import Charts
import Foundation
import SwiftUI

struct GlucoseTargetsView: ChartContent {
    let startMarker: Date
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
        let targetProfiles: [TargetProfile] = processFetchedTargets(bgTargets)

        // Draw target lines for each profile
        return ForEach(targetProfiles, id: \.self) { profile in
            LineMark(
                x: .value("Time", Date(timeIntervalSinceReferenceDate: profile.startTime)),
                y: .value("Target", profile.value)
            )
            .lineStyle(.init(lineWidth: 1))
            .foregroundStyle(Color.green.gradient)

            LineMark(
                x: .value("Time", Date(timeIntervalSinceReferenceDate: profile.endTime)),
                y: .value("Target", profile.value)
            )
            .lineStyle(.init(lineWidth: 1))
            .foregroundStyle(Color.green.gradient)
        }
    }

    /**
     Processes raw glucose target data into a list of target profiles for visualization.

     - Parameter rawTargets: The raw glucose target data containing offset and glucose values.
     - Returns: An array of `TargetProfile` objects, each representing a glucose target range for today and tomorrow.

     The function:
     - Converts glucose targets into profiles covering two consecutive days (today and tomorrow).
     - Calculates start and end times for each target based on the offsets provided.
     - Handles conversions between mg/dL and mmol/L as per user settings.
     - Ensures targets span across midnight to avoid data cutoff.

     Example:
     For a target at offset 0 (midnight) with low glucose value 70 mg/dL, the function generates two profiles:
     - One for today from midnight to the next target offset or end of the day.
     - Another for tomorrow covering the same time range.
     */
    private func processFetchedTargets(_ rawTargets: BGTargets) -> [TargetProfile] {
        var targetProfiles: [TargetProfile] = []

        // Ensure there are targets to process
        guard !rawTargets.targets.isEmpty else {
            print("Warning: No targets to process in rawTargets.")
            return []
        }

        let targets = rawTargets.targets

        // Base date is the start of the day for the startMarker
        let baseDate = Calendar.current.startOfDay(for: startMarker)

        // Process each target twice: once for today and once for tomorrow
        for index in 0 ..< (targets.count * 2) {
            // Calculate the day offset (0 for today, 1 for tomorrow)
            let dayOffset = index / targets.count
            let targetIndex = index % targets.count

            // Validate target index to ensure safety
            guard targetIndex < targets.count else {
                print("Error: Invalid target index \(targetIndex).")
                continue
            }

            // Fetch the target for the current iteration
            let target = targets[targetIndex]

            // Calculate the time offset for the current day
            let dayTimeOffset = TimeInterval(dayOffset * 24 * 60 * 60)

            // Calculate the start time for the current target
            let startTime = baseDate
                .addingTimeInterval(dayTimeOffset)
                .addingTimeInterval(TimeInterval(target.offset * 60))

            // Calculate the end time for the current target
            let endTime: Date = {
                if targetIndex + 1 < targets.count {
                    // End time is the start time of the next target within the same day
                    return baseDate
                        .addingTimeInterval(dayTimeOffset)
                        .addingTimeInterval(TimeInterval(targets[targetIndex + 1].offset * 60))
                } else {
                    // End time is the end of the day (midnight of the next day)
                    return baseDate.addingTimeInterval(dayTimeOffset + 24 * 60 * 60)
                }
            }()

            // Convert glucose value based on user unit preference (mg/dL or mmol/L)
            let targetValue = units == .mgdL ? target.low : target.low.asMmolL

            // Append the processed target profile to the list
            targetProfiles.append(
                TargetProfile(
                    value: targetValue,
                    startTime: startTime.timeIntervalSinceReferenceDate,
                    endTime: endTime.timeIntervalSinceReferenceDate
                )
            )
        }

        return targetProfiles
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
