import Foundation

/// Represents the "temp" object built in JS meal/history.js
struct MealInput {
    let timestamp: Date
    var carbs: Decimal? /// `current.carbs`
    var bolus: Decimal? /// from `current.amount` in Bolus events
    /// omitting nsCarbs, bwCarbs, journalCarbs

    enum InputType: String {
        case carbs
        case bolus
    }
}

private struct MealInputKey: Hashable {
    let timestamp: Date
    let type: MealInput.InputType
}

enum MealHistory {
    /// Converts carb and bolus records into a single, chronological list of MealInput,
    /// removing any duplicate entries of the same type whose timestamps are within ±2 seconds.
    /// - Parameters:
    ///   - pumpHistory: Array of PumpHistoryEvent (bolus events)
    ///   - carbHistory: Array of CarbsEntry (carb treatments)
    /// - Returns: A deduplicated array of MealInput, preserving original order but collapsing
    ///            any carb or bolus events that occur within 2 seconds of an earlier one.
    static func findMealInputs(
        pumpHistory: [PumpHistoryEvent],
        carbHistory: [CarbsEntry]
    ) -> [MealInput] {
        let carbInputs = carbHistory.compactMap { entry -> MealInput? in
            guard entry.carbs > 0 else { return nil }
            return MealInput(
                timestamp: entry.createdAt,
                carbs: entry.carbs,
                bolus: nil
            )
        }

        let bolusInputs = pumpHistory.compactMap { ev -> MealInput? in
            guard ev.type == .bolus, let amt = ev.amount else { return nil }
            return MealInput(
                timestamp: ev.timestamp,
                carbs: nil,
                bolus: amt
            )
        }

        let combinedIputs = carbInputs + bolusInputs
        var seenBuckets: [MealInput.InputType: Set<Int>] = [
            .carbs: Set(),
            .bolus: Set()
        ]

        var dedupedInputs: [MealInput] = []
        dedupedInputs.reserveCapacity(combinedIputs.count)

        for input in combinedIputs {
            let type: MealInput.InputType = input.carbs != nil ? .carbs : .bolus
            let tSec = Int(input.timestamp.timeIntervalSince1970)

            // check if any second in [tSec-2 ... tSec+2] is already in our bucket
            let bucket = seenBuckets[type]!
            let isDuplicate = (tSec - 2 ... tSec + 2).contains { bucket.contains($0) }

            if !isDuplicate {
                dedupedInputs.append(input)

                /// copies out bucket, mutates it, writes it back
                /// ensuring every entry exists at least once, but is properly deduped
                var newBucket = bucket
                newBucket.insert(tSec)
                seenBuckets[type] = newBucket
            }
        }

        return dedupedInputs
    }
}
