import Foundation

/// The bolus calculator's arithmetic, kept apart from its manager so every device recommends the same
/// bolus from the same inputs.
enum BolusCalculator {
    /// Calculates the recommended insulin dose based on various parameters
    static func calculate(_ input: CalculationInput, roundBolus: (Decimal) -> Decimal) -> CalculationResult {
        // insulin needed for the current blood glucose
        let targetDifference = input.currentBG - input.target

        let targetDifferenceInsulin = targetDifference / input.isf

        // more or less insulin because of bg trend in the last 15 minutes
        let fifteenMinutesInsulin = input.deltaBG / input.isf

        // determine whole COB for which we want to dose insulin for and then determine insulin for wholeCOB
        // we need to take backdated carbs into account - so we are using a freshly created (simulated) COB if carbs are backdated, otherwise it will default to the mostRecentDeterminations' COB value (as before)
        let wholeCob = min(Decimal(input.cob) + input.carbs, input.maxCOB)
        let wholeCobInsulin = wholeCob / input.carbRatio

        // determine how much the calculator reduces/ increases the bolus because of IOB
        let iobInsulinReduction = (-1) * input.iob

        // adding everything together
        // add a calc for the case that no fifteenMinInsulin is available
        let wholeCalc: Decimal
        if input.deltaBG != 0 {
            wholeCalc = (targetDifferenceInsulin + iobInsulinReduction + wholeCobInsulin + fifteenMinutesInsulin)
        } else {
            // add (rare) case that no glucose value is available -> maybe display warning?
            // if no bg is available, ?? sets its value to 0
            if input.currentBG == 0 {
                wholeCalc = (iobInsulinReduction + wholeCobInsulin)
            } else {
                wholeCalc = (targetDifferenceInsulin + iobInsulinReduction + wholeCobInsulin)
            }
        }

        // apply custom factor at the end of the calculations
        // apply custom factor if reduced bolus toggle in bolus calc config settings is on and the box for reduced bolus is checked (in RootView)
        var factoredInsulin = wholeCalc

        // Apply Recommended Bolus Percentage (input.fraction) and if selected apply Reduced Bolus Percentage (input.fattyMealFactor)
        // If factoredInsulin is negative, though, don't apply either
        if factoredInsulin > 0 {
            factoredInsulin *= input.fraction

            if input.useFattyMealCorrectionFactor {
                factoredInsulin *= input.fattyMealFactor
            }
        }

        // Calculate and add super bolus insulin if enabled
        var superBolusInsulin: Decimal = 0
        if input.useSuperBolus {
            superBolusInsulin = input.sweetMealFactor * input.basal
            factoredInsulin += superBolusInsulin
        }

        // the final result for recommended insulin amount
        var insulinCalculated: Decimal
        let isLoopStale = Date().timeIntervalSince(input.lastLoopDate) > 15 * 60

        // don't recommend insulin when current glucose or minPredBG is < 54 or last sucessful loop was over 15 minutes ago
        if input.currentBG < 54 || input.minPredBG < 54 || isLoopStale {
            insulinCalculated = 0
        } else {
            // no negative insulinCalculated
            insulinCalculated = max(factoredInsulin, 0)

            // don't exceed maxBolus
            insulinCalculated = min(insulinCalculated, input.maxBolus)

            // don't exceed maxIOB
            insulinCalculated = min(insulinCalculated, input.maxIOB - input.iob)

            // round calculated recommendation to allowed bolus increment
            insulinCalculated = roundBolus(insulinCalculated)
        }

        // one line per calculation: each step had its own, 19 lines for every calculation and about 2,500 a night
        // (27 October, second tester's log)
        func r(_ value: Decimal) -> String { String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue) }
        debug(
            .bolus,
            "Calculator: BG \(input.currentBG) (target diff \(targetDifference) → \(r(targetDifferenceInsulin)) U, 15 min \(r(fifteenMinutesInsulin)) U), COB \(wholeCob) g → \(r(wholeCobInsulin)) U, IOB \(r(iobInsulinReduction)) U, whole \(r(wholeCalc)) U, factored \(r(factoredInsulin)) U (super \(r(superBolusInsulin)) U), minPredBG \(input.minPredBG), loop stale \(isLoopStale) → \(insulinCalculated) U"
        )

        return CalculationResult(
            insulinCalculated: insulinCalculated,
            factoredInsulin: factoredInsulin,
            wholeCalc: wholeCalc,
            iobInsulinReduction: iobInsulinReduction,
            superBolusInsulin: superBolusInsulin,
            targetDifference: targetDifference,
            targetDifferenceInsulin: targetDifferenceInsulin,
            fifteenMinutesInsulin: fifteenMinutesInsulin,
            wholeCob: wholeCob,
            wholeCobInsulin: wholeCobInsulin
        )
    }

    /// The value of a daily schedule (basal, carb ratio, target, ISF) at `now`.
    static func scheduleValue(
        _ entries: [(start: String, value: Decimal)],
        at now: Date,
        calendar: Calendar = .current
    ) -> Decimal {
        for (index, entry) in entries.enumerated() {
            guard let entryTime = TherapySettingsUtil.parseTime(entry.start) else {
                debug(.bolus, "Invalid entry start time: \(entry.start)")
                continue
            }

            let entryComponents = calendar.dateComponents([.hour, .minute, .second], from: entryTime)
            let entryStartTime = calendar.date(
                bySettingHour: entryComponents.hour!,
                minute: entryComponents.minute!,
                second: entryComponents.second ?? 0, // Set seconds to 0 if not provided
                of: now
            )!

            let entryEndTime: Date
            if index < entries.count - 1 {
                if let nextEntryTime = TherapySettingsUtil.parseTime(entries[index + 1].start) {
                    let nextEntryComponents = calendar.dateComponents([.hour, .minute, .second], from: nextEntryTime)
                    entryEndTime = calendar.date(
                        bySettingHour: nextEntryComponents.hour!,
                        minute: nextEntryComponents.minute!,
                        second: nextEntryComponents.second ?? 0,
                        of: now
                    )!
                } else {
                    entryEndTime = calendar.date(byAdding: .day, value: 1, to: entryStartTime)!
                }
            } else {
                entryEndTime = calendar.date(byAdding: .day, value: 1, to: entryStartTime)!
            }

            if now >= entryStartTime, now < entryEndTime {
                return entry.value
            }
        }
        return 0
    }

    /// Current glucose is the newest reading regardless of age; the delta spans the readings of the
    /// last 20 minutes. `newestFirst` as stored, newest first.
    static func glucoseVariables(
        newestFirst: [(date: Date?, glucose: Decimal)],
        now: Date
    ) -> (currentBG: Decimal, deltaBG: Decimal) {
        let lastGlucose = newestFirst.first?.glucose ?? 0
        let twentyMinutesAgo = now.addingTimeInterval(-20 * 60)
        let recent = newestFirst.filter { ($0.date ?? .distantPast) > twentyMinutesAgo }
        let delta = recent.count >= 2 ? (recent.first?.glucose ?? 0) - (recent.last?.glucose ?? 0) : 0
        return (lastGlucose, delta)
    }
}

/// Input parameters required for bolus calculation
struct CalculationInput: Sendable {
    let carbs: Decimal // Carbohydrates to be consumed (in grams)
    let currentBG: Decimal // Current blood glucose level
    let deltaBG: Decimal // Blood glucose change in last 15 minutes
    let target: Decimal // Target blood glucose level
    let isf: Decimal // Insulin Sensitivity Factor
    let carbRatio: Decimal // Carb to insulin ratio
    let iob: Decimal // Insulin on Board
    let cob: Int16 // Carbs on Board
    let useFattyMealCorrectionFactor: Bool // Whether to apply reduced bolus correction
    let fattyMealFactor: Decimal // Factor for reduced bolus adjustment
    let useSuperBolus: Bool // Whether to use super bolus calculation
    let sweetMealFactor: Decimal // Factor for sweet meal adjustment
    let basal: Decimal // Current basal rate
    let fraction: Decimal // General correction factor
    let maxBolus: Decimal // Maximum allowed bolus
    let maxIOB: Decimal // Maximum allowed IOB to be used for rec. bolus calculation
    let maxCOB: Decimal // Maximum allowed COB to be used for rec. bolus calculation
    let minPredBG: Decimal // Minimum Predicted Glucose determined by Oref
    let lastLoopDate: Date // Date at which loop last completed successfully
}

/// Results of the bolus calculation
struct CalculationResult: Sendable {
    let insulinCalculated: Decimal // Final calculated insulin amount which respects limits
    let factoredInsulin: Decimal // Total calculation after adjustments
    let wholeCalc: Decimal // Total calculation before adjustments
    let iobInsulinReduction: Decimal // IOB reduction amount
    let superBolusInsulin: Decimal // Additional insulin for super bolus
    let targetDifference: Decimal // Difference from target BG
    let targetDifferenceInsulin: Decimal // Insulin needed for target difference
    let fifteenMinutesInsulin: Decimal // Trend-based insulin adjustment
    let wholeCob: Decimal // Total carbs (COB + new carbs)
    let wholeCobInsulin: Decimal // Insulin needed for total carbs
}
