import Foundation

extension Profile {
    /// Returns the basal rate for the given time (default: now), or 0 if not found.
    func basalFor(time: Date = Date()) -> Decimal {
        guard let entries = basalprofile, !entries.isEmpty else {
            return currentBasal ?? 0
        }

        let calendar = Calendar.current

        // Get today's midnight
        let startOfDay = calendar.startOfDay(for: time)
        let nowMinutes = calendar.dateComponents([.minute], from: startOfDay, to: time).minute ?? 0

        for (index, entry) in entries.enumerated() {
            let startMinutes = entry.minutes
            let endMinutes: Int

            if index < entries.count - 1 {
                endMinutes = entries[index + 1].minutes
            } else {
                endMinutes = 24 * 60 // 1440, end of day
            }

            if nowMinutes >= startMinutes, nowMinutes < endMinutes {
                return entry.rate
            }
        }
        return 0.1
    }

    /// Returns the ISF (insulin sensitivity factor) for the given time (default: now), or 200 if not found.
    func sensitivityFor(time: Date = Date()) -> Decimal {
        guard let isfProfile = isfProfile,
              !isfProfile.sensitivities.isEmpty
        else {
            // Fallback to single value, if present
            return sens ?? 200
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: time)
        let nowMinutes = calendar.dateComponents([.minute], from: startOfDay, to: time).minute ?? 0

        let entries = isfProfile.sensitivities.sorted { $0.offset < $1.offset }

        for (index, entry) in entries.enumerated() {
            let startMinutes = entry.offset
            let endMinutes: Int
            if index < entries.count - 1 {
                endMinutes = entries[index + 1].offset
            } else {
                endMinutes = 24 * 60 // 1440, end of day
            }

            if nowMinutes >= startMinutes, nowMinutes < endMinutes {
                return entry.sensitivity
            }
        }
        return sens ?? 200
    }

    /// Returns the carb ratio for the given time (default: now), or the top-level value, or 10 if not found.
    func carbRatioFor(time: Date = Date()) -> Decimal {
        // First: try using the dynamic schedule
        if let carbRatios = carbRatios, !carbRatios.schedule.isEmpty {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: time)
            let nowMinutes = calendar.dateComponents([.minute], from: startOfDay, to: time).minute ?? 0

            let entries = carbRatios.schedule.sorted { $0.offset < $1.offset }

            for (index, entry) in entries.enumerated() {
                let startMinutes = entry.offset
                let endMinutes: Int
                if index < entries.count - 1 {
                    endMinutes = entries[index + 1].offset
                } else {
                    endMinutes = 24 * 60 // 1440, end of day
                }

                if nowMinutes >= startMinutes, nowMinutes < endMinutes {
                    return entry.ratio
                }
            }
        }
        // Second: fallback to flat profile value if present
        if let carbRatio = self.carbRatio {
            return carbRatio
        }
        // Third: fallback default (safe assumption)
        return 30
    }
}
