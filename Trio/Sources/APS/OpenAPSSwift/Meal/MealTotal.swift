import Foundation

struct ComputedCarbs: Codable {
    var carbs: Decimal
    var mealCOB: Decimal
    var currentDeviation: Decimal?
    var maxDeviation: Decimal
    var minDeviation: Decimal
    var slopeFromMaxDeviation: Decimal
    var slopeFromMinDeviation: Decimal
    var allDeviations: [Decimal]
    var lastCarbTime: TimeInterval

    enum CodingKeys: String, CodingKey {
        case carbs
        case mealCOB
        case currentDeviation
        case maxDeviation
        case minDeviation
        case slopeFromMaxDeviation
        case slopeFromMinDeviation
        case allDeviations
        case lastCarbTime
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(carbs, forKey: .carbs)
        try container.encode(mealCOB, forKey: .mealCOB)
        try container.encode(maxDeviation, forKey: .maxDeviation)
        try container.encode(minDeviation, forKey: .minDeviation)
        try container.encode(slopeFromMaxDeviation, forKey: .slopeFromMaxDeviation)
        try container.encode(slopeFromMinDeviation, forKey: .slopeFromMinDeviation)
        try container.encode(allDeviations, forKey: .allDeviations)
        try container.encode(lastCarbTime, forKey: .lastCarbTime)

        if let currentDeviation = currentDeviation {
            try container.encode(currentDeviation, forKey: .currentDeviation)
        } else {
            try container.encodeNil(forKey: .currentDeviation)
        }
    }
}

struct IOBInput {
    var profile: Profile
    let history: [PumpHistoryEvent]
    // var to enable input mutation
    var clock: Date
}

struct COBInputs {
    let glucoseData: [BloodGlucose]
    // var to enable input mutations
    var iobInputs: IOBInput
    let basalProfile: [BasalProfileEntry]
    var mealDate: Date
    var carbImpactDate: Date?
}

enum MealTotal {
    /// Calculates the effective carbohydrates on board (COB) and glucose deviations
    /// resulting from recent meal entries within the user’s absorption window.
    ///
    /// This function:
    /// 1. Filters `treatments` to only those within `profile.maxMealAbsorptionTime` hours before `time`.
    /// 2. Iterates each carb entry (≥1 g), calling `MealCob.detectCarbAbsorption` in CI mode
    ///    (last ~45 min) to estimate how much of the accumulated carbs remain unabsorbed,
    ///    tracking the peak “COB driver” and removing any extra carbs that never drove COB.
    /// 3. Subtracts out those “extra” carbs to yield the true total carbs counted.
    /// 4. Performs a final COB + deviation pass anchored at the earliest valid carb timestamp,
    ///    again in CI mode, to compute:
    ///    – `currentDeviation`, `maxDeviation`, `minDeviation`,
    ///    – `slopeFromMaxDeviation`, `slopeFromMinDeviation`,
    ///    – the full series `allDeviations`,
    ///    – and applies profile caps (`maxCOB`) and “zombie‐carb” safety (zero COB if no dev).
    ///
    /// - Parameters:
    ///   - treatments:   list of past carb-and-bolus `MealInput` events
    ///   - pumpHistory:  insulin pump history for IOB calculations
    ///   - profile:      user profile (carb ratio, ISF, maxMealAbsorptionTime, maxCOB, etc.)
    ///   - basalProfile: basal insulin schedule
    ///   - glucose:      BG readings used to bucket and compute deviations
    ///   - time:         the “now” timestamp at which to evaluate COB & deviations
    ///
    /// - Returns:
    ///   A `ComputedCarbs` struct containing:
    ///     • `carbs` – total carbs counted
    ///     • `mealCOB` – carbs on board at peak
    ///     • `currentDeviation`, `maxDeviation`, `minDeviation`
    ///     • `slopeFromMaxDeviation`, `slopeFromMinDeviation`
    ///     • `allDeviations` – the deviation history
    ///     • `lastCarbTime` – timestamp of the most recent carb used
    ///
    /// - Throws: any errors from `MealCob.detectCarbAbsorption`.
    static func recentCarbs(
        treatments: [MealInput],
        pumpHistory: [PumpHistoryEvent],
        profile: Profile,
        basalProfile: [BasalProfileEntry],
        glucose: [BloodGlucose],
        time: Date
    ) throws -> ComputedCarbs? {
        guard treatments.isNotEmpty else { return nil }

        // Re-assign to a var, so it can be sorted
        var _treatments = treatments
        var profile = profile

        // Define defaults
        var carbs = Decimal(0)
        let mealCarbTime: TimeInterval = time.timeIntervalSince1970
        var lastCarbTime: TimeInterval = 0

        let iobInputs = IOBInput(profile: profile, history: pumpHistory, clock: time)
        var cobInputs = COBInputs(
            glucoseData: glucose,
            iobInputs: iobInputs,
            basalProfile: basalProfile,
            mealDate: Date(timeIntervalSince1970: mealCarbTime)
        )
        var mealCOB = Decimal(0)

        _treatments.sort(by: {
            $0.timestamp > $1.timestamp
        })

        var carbsToRemove = Decimal(0)

        for treatment in _treatments {
            let now = time.timeIntervalSince1970

            // Use new maxMealAbsorptionTime setting here instead of default 6 hrs
            let carbWindow = now - TimeInterval(hours: Double(truncating: profile.maxMealAbsorptionTime as NSNumber))

            let treatmentDate = treatment.timestamp
            let treatmentTime = treatmentDate.timeIntervalSince1970

            if treatmentTime > carbWindow, treatmentTime <= now {
                if let _carbs = treatment.carbs, _carbs >= 1 {
                    carbs += _carbs

                    cobInputs.mealDate = treatmentDate
                    lastCarbTime = max(lastCarbTime, treatmentTime)

                    let myCarbsAbsorbed = try MealCob.detectCarbAbsorption(
                        clock: &cobInputs.iobInputs.clock,
                        glucose: cobInputs.glucoseData,
                        pumpHistory: cobInputs.iobInputs.history,
                        basalProfile: cobInputs.basalProfile,
                        profile: &cobInputs.iobInputs.profile,
                        mealDate: cobInputs.mealDate,
                        carbImpactDate: cobInputs.carbImpactDate
                    ).carbsAbsorbed

                    // TODO: add logging?
                    let myMealCOB = max(0, carbs - myCarbsAbsorbed)
                    mealCOB = max(mealCOB, myMealCOB)

                    if myMealCOB < mealCOB {
                        carbsToRemove += treatment.carbs ?? 0
                    } else {
                        carbsToRemove = 0
                    }
                }
            }
        }

        // only include carbs actually used in calculating COB
        carbs -= carbsToRemove

        // calculate the current deviation and steepest deviation downslope over the last hour
        cobInputs.carbImpactDate = time
        cobInputs.mealDate = time - Double(profile.maxMealAbsorptionTime) * 3600

        // set a hard upper limit on COB to mitigate impact of erroneous or malicious carb entry
        mealCOB = min(profile.maxCOB, mealCOB)
        /// omiting maxCOB check here, the setting is not Optional in Swift and must be part of profile

        let finalCobResult = try MealCob.detectCarbAbsorption(
            clock: &cobInputs.iobInputs.clock,
            glucose: cobInputs.glucoseData,
            pumpHistory: cobInputs.iobInputs.history,
            basalProfile: cobInputs.basalProfile,
            profile: &cobInputs.iobInputs.profile,
            mealDate: cobInputs.mealDate,
            carbImpactDate: cobInputs.carbImpactDate
        )

        // the comment in JS says this:
        //    if currentDeviation is null or maxDeviation is 0, set mealCOB to 0
        //    for zombie-carb safety
        // But the code only checks if it's defined, not the value
        if finalCobResult.allDeviations.isEmpty {
            mealCOB = 0
        }

        let currentDeviation = finalCobResult.allDeviations.isEmpty ? nil : finalCobResult.currentDeviation.rounded(scale: 2)

        return ComputedCarbs(
            carbs: carbs,
            mealCOB: mealCOB,
            currentDeviation: currentDeviation,
            maxDeviation: finalCobResult.maxDeviation.rounded(scale: 2),
            minDeviation: finalCobResult.minDeviation.rounded(scale: 2),
            slopeFromMaxDeviation: finalCobResult.slopeFromMaxDeviation.rounded(scale: 3),
            slopeFromMinDeviation: finalCobResult.slopeFromMinDeviation.rounded(scale: 3),
            allDeviations: finalCobResult.allDeviations,
            lastCarbTime: (lastCarbTime * 1000).rounded()
        )
    }
}
