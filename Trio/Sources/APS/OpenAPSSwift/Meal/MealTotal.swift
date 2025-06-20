import Foundation

struct ComputedCarbs: Codable {
    var carbs: Decimal
    var mealCOB: Decimal
    var currentDeviation: Decimal
    var maxDeviation: Decimal
    var minDeviation: Decimal
    var slopeFromMaxDeviation: Decimal
    var slopeFromMinDeviation: Decimal
    var allDeviations: [Decimal]
    var lastCarbTime: TimeInterval
}

struct IOBInput {
    let profile: Profile
    let history: [PumpHistoryEvent]
}

struct COBInputs {
    let glucoseData: [BloodGlucose]
    let iobInputs: IOBInput
    let basalProfile: [BasalProfileEntry]
    var mealDate: Date
    var carbImpactDate: Date?
}

enum MealTotal {
    static func recentCarbs(
        treatments: [MealInput],
        pumpHistory: [PumpHistoryEvent],
        profile: Profile,
        basalProfile: [BasalProfileEntry],
        glucose: [BloodGlucose],
        time: Date
    ) throws -> ComputedCarbs? {
        guard treatments.isNotEmpty else { return nil }

        var _treatments = treatments
        var carbs = Decimal(0)
        let mealCarbTime: TimeInterval = time.timeIntervalSince1970
        var lastCarbTime: TimeInterval = 0

        let iobInputs = IOBInput(profile: profile, history: pumpHistory)
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
            var carbWindow = now - TimeInterval(hours: Double(truncating: profile.maxMealAbsorptionTime as NSNumber))

            let treatmentDate = treatment.timestamp
            let treatmentTime = treatmentDate.timeIntervalSince1970

            if treatmentTime > carbWindow, treatmentTime <= now {
                if var _carbs = treatment.carbs, _carbs >= 1 {
                    carbs += _carbs

                    cobInputs.mealDate = treatmentDate
                    lastCarbTime = max(lastCarbTime, treatmentTime)

                    let myCarbsAbsorbed = try MealCob.detectCarbAbsorption(
                        glucose: cobInputs.glucoseData,
                        pumpHistory: cobInputs.iobInputs.history,
                        basalProfile: cobInputs.basalProfile,
                        profile: cobInputs.iobInputs.profile,
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
            glucose: cobInputs.glucoseData,
            pumpHistory: cobInputs.iobInputs.history,
            basalProfile: cobInputs.basalProfile,
            profile: cobInputs.iobInputs.profile,
            mealDate: cobInputs.mealDate,
            carbImpactDate: cobInputs.carbImpactDate
        )

        // if currentDeviation is null or maxDeviation is 0, set mealCOB to 0 for zombie-carb safety
        if finalCobResult.maxDeviation == 0 || finalCobResult.allDeviations.isEmpty {
            mealCOB = 0
        }

        return ComputedCarbs(
            carbs: carbs,
            mealCOB: mealCOB,
            currentDeviation: finalCobResult.currentDeviation.rounded(scale: 2),
            maxDeviation: finalCobResult.maxDeviation.rounded(scale: 2),
            minDeviation: finalCobResult.minDeviation.rounded(scale: 2),
            slopeFromMaxDeviation: finalCobResult.slopeFromMaxDeviation.rounded(scale: 3),
            slopeFromMinDeviation: finalCobResult.slopeFromMinDeviation.rounded(scale: 3),
            allDeviations: finalCobResult.allDeviations,
            lastCarbTime: lastCarbTime
        )
    }
}
