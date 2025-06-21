import Foundation

struct DeterminationRequest {
    let glucose:        [BloodGlucose]
    let pumpHistory:    [PumpHistoryEvent]
    let carbTreatments: [MealInput]
    let currentTemp:    TempBasal
    let preferences:    Preferences
    let custom:         TrioCustomOrefVariables
    let date:           Date
}

protocol SMBProvider {
    func isSMBEnabled(
        glucose: BloodGlucose,
        profile: Profile,
        autosens: Autosens,
        date: Date
    ) -> Bool
    
    // TODO: handle oref JS's enable_smb() logic
}

struct DeterminationGenerator {
    let profileGenerator: ProfileGenerator
    let iobGenerator: IobGenerator
    let autosensGenerator: AutosensGenerator
    let mealProcessor: MealTotal
    let smbProvider: SMBProvider

    func generate(
        request _: DeterminationRequest
    ) throws -> Determination? {
        
        // FIXME: implement... (return type will not be Optional; just to shut up the compiler)
        
        /// Current determine basal (if we ignore forecasting logic; already modularized) does:
        /// 1. Validate CGM → cancel if needed
        /// 2. Override basal → log
        /// 3. Load targets → error if missing
        /// 4. Adjust sensitivity → maybe adjust basal/target
        /// 5. Check IOB consistency → cancel if needed
        /// 6. Compute deviation/eventualBG → log
        /// 7. Ignore Forecast & but guard-BG
        /// 8. Compute carbsReq → we could move this to MEAL
        /// 9. Decide temp basal → we could do a tempBasalGenerator ?
        
        nil
    }
}
