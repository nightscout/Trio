import Foundation

struct ComputedCarbs: Codable {
    var carbs: Decimal
    var nsCarbs: Decimal
    var bwCarbs: Decimal
    var journalCarbs: Decimal
    var mealCOB: Decimal
    var currentDeviation: Decimal
    var maxDeviation: Decimal
    var minDeviation: Decimal
    var slopeFromMaxDeviation: Decimal
    var slopeFromMinDeviation: Decimal
    var allDeviations: [Decimal]
    var lastCarbTime: TimeInterval
    var bwFound: Bool
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
    var ciDate: Date?
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
        var nsCarbs = Decimal(0)
        var bwCarbs = Decimal(0)
        var journalCarbs = Decimal(0)
        let mealCarbTime: TimeInterval = time.timeIntervalSince1970
        var lastCarbTime: TimeInterval = 0
        var bwFound: Bool = false

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
        var nsCarbsToRemove = Decimal(0)
        var bwCarbsToRemove = Decimal(0)
        var journalCarbsToRemove = Decimal(0)

        for treatment in _treatments {
            let now = time.timeIntervalSince1970

            // Use new maxMealAbsorptionTime setting here instead of default 6 hrs
            var carbWindow = now - TimeInterval(hours: Double(truncating: profile.maxMealAbsorptionTime as NSNumber))

            let treatmentDate = treatment.timestamp
            let treatmentTime = treatmentDate.timeIntervalSince1970

            if treatmentTime > carbWindow, treatmentTime <= now {
                if var _carbs = treatment.carbs, _carbs >= 1 {
                    if var _nsCarbs = treatment.nsCarbs, _nsCarbs >= 1 {
                        nsCarbs += _nsCarbs
                    } else if var _bwCarbs = treatment.bwCarbs, _bwCarbs >= 1 {
                        bwCarbs += _bwCarbs
                        bwFound = true
                    } else if var _journalCarbs = treatment.journalCarbs, _journalCarbs >= 1 {
                        journalCarbs += _journalCarbs
                    } else {
                        print("Treatment carbs unclassified: \(treatment)")
                    }

                    carbs += _carbs

                    cobInputs.mealDate = treatmentDate
                    lastCarbTime = max(lastCarbTime, treatmentTime)

                    let myCarbsAbsorbed = try MealCob.detectCarbAbsorption(
                        glucose: cobInputs.glucoseData,
                        pumpHistory: cobInputs.iobInputs.history,
                        basalProfile: cobInputs.basalProfile,
                        profile: cobInputs.iobInputs.profile,
                        mealDate: cobInputs.mealDate,
                        ciDate: cobInputs.ciDate
                    ).carbsAbsorbed

                    // TODO: add logging?
                    let myMealCOB = max(0, carbs - myCarbsAbsorbed)
                    mealCOB = max(mealCOB, myMealCOB)

                    if myMealCOB < mealCOB {
                        carbsToRemove += treatment.carbs ?? 0
                        if var _nsCarbs = treatment.nsCarbs, nsCarbs >= 1 {
                            nsCarbsToRemove += _nsCarbs
                        } else if var _bwCarbs = treatment.bwCarbs, bwCarbs >= 1 {
                            bwCarbsToRemove += _bwCarbs
                        } else if var _journalCarbs = treatment.journalCarbs, journalCarbs >= 1 {
                            journalCarbsToRemove += _journalCarbs
                        }
                    } else {
                        carbsToRemove = 0
                        nsCarbsToRemove = 0
                        bwCarbsToRemove = 0
                    }
                }
            }
        }

        // only include carbs actually used in calculating COB
        carbs -= carbsToRemove
        nsCarbs -= nsCarbsToRemove
        bwCarbs -= bwCarbsToRemove
        journalCarbs -= journalCarbsToRemove

        // calculate the current deviation and steepest deviation downslope over the last hour
        cobInputs.ciDate = time
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
            ciDate: cobInputs.ciDate
        )

        // if currentDeviation is null or maxDeviation is 0, set mealCOB to 0 for zombie-carb safety
        if finalCobResult.maxDeviation == 0 || finalCobResult.allDeviations.isEmpty {
            mealCOB = 0
        }

        return ComputedCarbs(
            carbs: carbs,
            nsCarbs: nsCarbs,
            bwCarbs: bwCarbs,
            journalCarbs: journalCarbs,
            mealCOB: mealCOB,
            currentDeviation: finalCobResult.currentDeviation.rounded(scale: 2),
            maxDeviation: finalCobResult.maxDeviation.rounded(scale: 2),
            minDeviation: finalCobResult.minDeviation.rounded(scale: 2),
            slopeFromMaxDeviation: finalCobResult.slopeFromMaxDeviation.rounded(scale: 3),
            slopeFromMinDeviation: finalCobResult.slopeFromMinDeviation.rounded(scale: 3),
            allDeviations: finalCobResult.allDeviations,
            lastCarbTime: lastCarbTime,
            bwFound: bwFound
        )
    }
}
