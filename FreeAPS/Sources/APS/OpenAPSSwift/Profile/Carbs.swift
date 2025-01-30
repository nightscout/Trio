import Foundation

struct Carbs {
    static func carbRatioLookup(carbRatio: CarbRatios, now: Date = Date()) -> Decimal? {
        // Get last schedule as default
        guard let lastSchedule = carbRatio.schedule.last else { return nil }
        var currentRatio = lastSchedule.ratio

        // Find matching schedule for current time
        do {
            for (curr, next) in zip(carbRatio.schedule, carbRatio.schedule.dropFirst()) {
                if try now.isMinutesFromMidnightWithinRange(lowerBound: curr.offset, upperBound: next.offset) {
                    currentRatio = curr.ratio
                    break
                }
            }
        } catch {
            return nil
        }

        // Check for invalid values
        if currentRatio < 3 || currentRatio > 150 {
            warning(.openAPS, "Warning: carbRatio of \(currentRatio) out of bounds.")
            return nil
        }

        // Convert exchanges to grams
        switch carbRatio.units {
        case .exchanges:
            return 12 / currentRatio
        case .grams:
            return currentRatio
        }
    }
}
