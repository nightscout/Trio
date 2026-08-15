import Foundation

// I removed the cache that the Javascript version has to help keep it simple
struct Isf {
    /// Sorted schedule for repeated per-bucket lookups; selection mirrors `isfLookup` exactly
    struct PreparedSchedule {
        private let sorted: [(offset: Int, sensitivity: Decimal)]

        init(_ isfProfile: ComputedInsulinSensitivities) {
            sorted = isfProfile.sensitivities
                .sorted { $0.offset < $1.offset }
                .map { ($0.offset, $0.sensitivity) }
        }

        /// Returns -1 on a bad schedule, matching the JS error value
        func sensitivity(at timestamp: Date) throws -> Decimal {
            guard sorted.first?.offset == 0, let last = sorted.last else {
                return -1
            }
            guard sorted.count > 1 else {
                return last.sensitivity
            }
            guard let minutes = timestamp.minutesSinceMidnight else {
                throw CalendarError.invalidCalendar
            }
            for (curr, next) in zip(sorted, sorted.dropFirst()) where minutes >= curr.offset && minutes < next.offset {
                return curr.sensitivity
            }
            return last.sensitivity
        }
    }

    static func isfLookup(
        isfDataInput: InsulinSensitivities,
        timestamp: Date
    ) throws -> (Decimal, ComputedInsulinSensitivities) {
        let now = timestamp

        let isfData = isfDataInput.computedInsulinSensitivies()

        // Sort sensitivities by offset
        let sortedSensitivities = isfData.sensitivities.sorted { $0.offset < $1.offset }

        // Verify first offset is 0
        guard let firstSensitivity = sortedSensitivities.first,
              firstSensitivity.offset == 0
        else {
            return (-1, isfData)
        }

        // Default to last entry
        guard var isfSchedule = sortedSensitivities.last else {
            return (-1, isfData)
        }

        var endMinutes = 1440

        // Find matching sensitivity for current time
        for (curr, next) in zip(sortedSensitivities, sortedSensitivities.dropFirst()) {
            if try now.isMinutesFromMidnightWithinRange(lowerBound: curr.offset, upperBound: next.offset) {
                endMinutes = next.offset
                isfSchedule = curr
                break
            }
        }

        // in the Javascript implementation they cache the last entry
        // which we don't do, but in the process they mutate the input
        // which is visible in Profile. This logic is to update our
        // input with the new endOffset parameter

        let updatedSchedule = isfData.sensitivities.map { sensitivity in
            if sensitivity.id == isfSchedule.id {
                return ComputedInsulinSensitivityEntry(
                    sensitivity: sensitivity.sensitivity,
                    offset: sensitivity.offset,
                    start: sensitivity.start,
                    endOffset: endMinutes,
                    id: sensitivity.id
                )
            } else {
                return sensitivity
            }
        }

        return (
            isfSchedule.sensitivity,
            ComputedInsulinSensitivities(
                units: isfData.units,
                userPreferredUnits: isfData.userPreferredUnits,
                sensitivities: updatedSchedule
            )
        )
    }
}
