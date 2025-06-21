import Foundation

struct DeterminationInputs {
    let profile: Profile
    let currentTemp: TempBasal
    let iobData: IobResult
    let autosensData: Autosens
    let mealData: ComputedCarbs?
    let reservoirData: Reservoir
    let currentTime: Date
}

protocol OverrideHandler {
    func overrideProfileParameters(profile: Profile, override: Override?) throws -> Profile

    // TODO: handle mutation of profile parameters that the user can alter using Overrides
    /// This could also possibly be handled via an extension of our existing `ProfileGenerator` (?)
}

struct DeterminationGenerator {
    let profileGenerator: ProfileGenerator
    let iobGenerator: IobGenerator
    let autosensGenerator: AutosensGenerator
    let mealProcessor: MealTotal

    // override data can just be fetched from the DB
    // handling via overrideManager ?

    func generate(
        request _: DeterminationInputs
    ) throws -> Determination? {
        // FIXME: implement... (return type will not be Optional; just to shut up the compiler)

        // trio-oref signature:
//        function determine_basal(glucose_status, currenttemp, iob_data, profile, autosens_data, meal_data, tempBasalFunctions, microBolusAllowed, reservoir_data, currentTime, pumphistory, preferences, basalprofile, trio_custom_variables, middleWare) {

        // openaps/oref0 signature:
//        function determine_basal(glucose_status, currenttemp, iob_data, profile, autosens_data, meal_data, tempBasalFunctions, microBolusAllowed, reservoir_data, currentTime) {

        /// We also need a call to glucose-get-last here (JS passes object `glucoseStatus`) → could be a simple function in GlucoseStorage
        /// We also need the tempBasal helpers (JS passes object `tempBasalFunctions` with functions)
        /// `tempBasalFunctions.getMaxSafeBasal` should be a helper function in or extension of`TrioSettings.swift`
        /// `tempBasalFunctions.setTempBasal` is a helper function utilizing pass by value of `rT` ("requested Temp") and adjusting `rT.duration` and `rT.rate`… can be an extension / helper fn of `DeterminationGenerator` itself
        /// TLDR; we could omit the 2 parameters `glucoseStatus` and `tempBasalFunctions`

        /// OTHER PARAMS:
        ///
        /// JS oref has `reservoir_data`; we have that on file via `loadFileFromStorageAsync(name: Monitor.reservoir)`
        /// NOT NEEDED: `pumphistory` → we no longer calculate TDD in determine
        /// NOT NEEDED: `preferences`, only used for dynamic ISF → pull this out
        /// NOT NEEDED: `basalprofile`, was used for TDD calc as well → remove
        /// NOT NEEDED: `trio_custom_variables` was used for (1) override handling, (2) SMB enabling → we should handle (1) in service of its own, and (2) already outlined via SMBProvider
        /// `microBolusAllowed` is currently HARD-CODED (!) to `true`… we always allow microbolusing and only handle this via the various SMB settings → remove ?

        /// All input params can EITHER be passed directly, OR…
        /// we handle it via an encapsulated struct (I chose DeterminationInputs
        // TODO: Do we want store algorithm input *and* output?

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
        

        // TODO: how to handle output?
        // TODO: how to handle logging?
        
        nil
    }
}

extension DeterminationGenerator {
    func calculateExpectedDelta(
        targetGlucose: Decimal,
        eventualGlucose: Decimal,
        glucoseImpact: Decimal
    ) -> Decimal {
        // JS expects glucose to rise/fall at rate of glucose impact
        // adjusted by the rate at which glucose would need to rise/fall
        // to move eventual glucose to target over a 2 hr window
        // TODO: expects that glucose can only be available in 5min chunks. do we need to change this handling?
        
        let fiveMinuteBlocks = (2 * 60) / 5
        let delta = targetGlucose - eventualGlucose
        return glucoseImpact + Decimal(Int(delta) / fiveMinuteBlocks).rounded(toPlaces: 1)

    }
    
    func isSMBEnabled(
        glucose _: BloodGlucose,
        profile _: Profile,
        autosens _: Autosens,
        date _: Date
    ) -> Bool {
        // TODO: handle oref JS's enable_smb() logic

        true
    }
}
