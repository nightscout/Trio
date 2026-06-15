import Foundation

extension ComputedInsulinSensitivities {
    /// Returns the insulin sensitivity (ISF) for a specific Date (using the closest entry).
    func sensitivity(for date: Date) -> Decimal? {
        guard !sensitivities.isEmpty else { return nil }
        // Assumes all offsets are in minutes from midnight
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minutesSinceMidnight = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        // Find the entry whose offset is the largest but not greater than the time
        let sorted = sensitivities.sorted(by: { $0.offset < $1.offset })
        var current = sorted.first
        for entry in sorted {
            if entry.offset <= minutesSinceMidnight {
                current = entry
            } else {
                break
            }
        }
        return current?.sensitivity
    }
}
