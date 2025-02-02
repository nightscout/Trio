import Foundation

extension Home.StateModel {
    /**
     Processes raw glucose target data into a list of target profiles for visualization.

     - Parameters:
        - rawTargets: The raw glucose target data containing offset and glucose values.
        - startMarker: The reference date to start the target profiles from.
     - Returns: An array of `TargetProfile` objects, each representing a glucose target range starting from the day of the startMarker and ending two days later.

     The function:
     - Converts glucose targets into profiles covering three consecutive days (day of startMarker, day after startMarker and day after that).
     - Calculates start and end times for each target based on the offsets provided.
     - Handles conversions between mg/dL and mmol/L as per user settings.
     - Ensures targets span across midnight to avoid data cutoff.
     */
    func processFetchedTargets(_ rawTargets: BGTargets, startMarker: Date) -> [TargetProfile] {
        var targetProfiles: [TargetProfile] = []

        // Ensure there are targets to process
        guard !rawTargets.targets.isEmpty else {
            debugPrint("\(DebuggingIdentifiers.failed) Warning: No targets to process in rawTargets.")
            return []
        }

        let targets = rawTargets.targets

        // Base date is the start of the day for the startMarker
        let baseDate = Calendar.current.startOfDay(for: startMarker)

        // Process each target three times
        for index in 0 ..< (targets.count * 3) {
            // Calculate the day offset (0 for today, 1 for tomorrow, 2 for day after)
            let dayOffset = index / targets.count
            let targetIndex = index % targets.count

            // Validate target index to ensure safety
            guard targetIndex < targets.count else {
                debugPrint("\(DebuggingIdentifiers.failed) Error: Invalid target index \(targetIndex).")
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
