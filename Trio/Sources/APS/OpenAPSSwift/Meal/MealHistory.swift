import Foundation

/// Represents the "temp" object built in JS meal/history.js
struct MealInput {
    let timestamp: Date
    var carbs: Decimal? /// `current.carbs`
    var nsCarbs: Decimal? /// `current.carbs` in NS
    var bolus: Decimal? /// from `current.amount` in Bolus events
    var journalCarbs: Decimal?
    var bwCarbs: Decimal?
    // TODO: we probably do not need nsCarbs, journalCarbs, and bwCarbs
}

enum MealHistory {
    /// Checks if `array` contains a MealInput with an entry that is ± 2 seconds around `t`.
    /// and a non-nil property given by propName ("carbs", "bolus", etc.).
    static func arrayHasElementWithSameTimestampAndProperty(
        mealInputs: [MealInput],
        t: Date,
        propName: String
    ) -> Bool {
        // Create upper and lower bound, i.e. ± 2 seconds around t
        let tMin = t.addingTimeInterval(-2)
        let tMax = t.addingTimeInterval(2)

        return mealInputs.contains { input in
            // Timestamp close enough?
            guard input.timestamp >= tMin, input.timestamp <= tMax else {
                return false
            }

            // Check the property name
            switch propName {
            case "carbs":
                return input.carbs != nil
            case "bolus":
                return input.bolus != nil
            default:
                return false
            }
        }
    }

    // the overall function signature (from oref) should be this one:
    //    static func findMealInputs(
    //        pumpHistory: [PumpHistoryEvent],
    //        profile _: Profile,
    //        basalProfile _: [BasalProfileEntry],
    //        clock _: Date,
    //        carbHistory: [CarbsEntry],
    //        glucoseHistory _: [BloodGlucose]
    //    ) -> [MealInput] {
    // however, we only require pumpHistory and carbHistory, so omiting the unused parameters
    static func findMealInputs(
        pumpHistory: [PumpHistoryEvent],
        carbHistory: [CarbsEntry]
    ) -> [MealInput] {
        var mealInputs: [MealInput] = []
        var duplicates = 0

        // Process carbHistory
        for current in carbHistory {
            // The JS code checks `if (current.carbs && current.created_at)`
            // In Swift, that's basically "non-nil carbs" and we rely on the type's Date.
            if current.carbs > 0 {
                let temp = MealInput(
                    timestamp: current.createdAt,
                    carbs: current.carbs,
                    nsCarbs: current.carbs,
                    bolus: nil,
                    journalCarbs: nil,
                    bwCarbs: nil
                )

                if !arrayHasElementWithSameTimestampAndProperty(
                    mealInputs: mealInputs,
                    t: current.createdAt,
                    propName: "carbs"
                ) {
                    mealInputs.append(temp)
                } else {
                    duplicates += 1
                }
            }
        }

        // Process pumpHistory
        for current in pumpHistory {
            // bolus event handling
            if current.type == .bolus, let amt = current.amount {
                let temp = MealInput(
                    timestamp: current.timestamp,
                    carbs: nil,
                    nsCarbs: nil,
                    bolus: amt,
                    journalCarbs: nil,
                    bwCarbs: nil
                )

                if !arrayHasElementWithSameTimestampAndProperty(
                    mealInputs: mealInputs,
                    t: current.timestamp,
                    propName: "bolus"
                ) {
                    mealInputs.append(temp)
                } else {
                    duplicates += 1
                }
            }

            // Trio will never send any pump history contents of the following types to oref
            // Ignoring for JavaScript -> Swift port.
            // .bolusWizard
            // .mealBolus
            // .correctionBolus
            // .snackBolus
            // .nsCarbCorrection
            // .journalCarbs
            // and the `carbsVal = current.carbInput` handling
        }

        // We can also omit the deferred bolus wizard input processing
        // TODO: log duplicates?

        return mealInputs
    }
}
