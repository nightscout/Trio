function generate(pumphistory_data, profile_data, glucose_data, pumpprofile_data, carb_data = {} , categorize_uam_as_basal = false, tune_insulin_curve = false) {
    if (typeof(profile_data.carb_ratio) === 'undefined' || profile_data.carb_ratio < 0.1) {
        if (typeof(pumpprofile_data.carb_ratio) === 'undefined' || pumpprofile_data.carb_ratio < 0.1) {
            console.log('{ "carbs": 0, "mealCOB": 0, "reason": "carb_ratios ' + profile_data.carb_ratio + ' and ' + pumpprofile_data.carb_ratio + ' out of bounds" }');
            return console.error("Error: carb_ratios " + profile_data.carb_ratio + ' and ' + pumpprofile_data.carb_ratio + " out of bounds");
        } else {
            profile_data.carb_ratio = pumpprofile_data.carb_ratio;
        }
    }

    // get insulin curve from pump profile that is maintained
    profile_data.curve = pumpprofile_data.curve;

    // Pump profile has an up to date copy of useCustomPeakTime from preferences
    // If the preferences file has useCustomPeakTime use the previous autotune dia and PeakTime.
    // Otherwise, use data from pump profile.
    if (!pumpprofile_data.useCustomPeakTime) {
      profile_data.dia = pumpprofile_data.dia;
      profile_data.insulinPeakTime = pumpprofile_data.insulinPeakTime;
    }

    // Always keep the curve value up to date with what's in the user preferences
    profile_data.curve = pumpprofile_data.curve;

    // Have to sort history - NS sort doesn't account for different zulu and local timestamps
    pumphistory_data.sort( function( firstValue, secondValue ) {
        try {
            var a = new Date(firstValue.timestamp);
            var b = new Date(secondValue.timestamp);
            return b.getTime() - a.getTime();
        } catch(e) {
            return 0;
        }
    } );

    inputs = {
      history: pumphistory_data
    , profile: profile_data
    , pumpprofile: pumpprofile_data
    , carbs: carb_data
    , glucose: glucose_data
    , categorize_uam_as_basal: categorize_uam_as_basal
    , tune_insulin_curve: tune_insulin_curve
    };

    return freeaps_autotunePrep(inputs);
}
