function generate(pumphistory_data, profile_data, clock_data, autosens_data, zeroTempDuration) {
    var inputs = {
        history: pumphistory_data
        , profile: profile_data
        , clock: clock_data
    };

    if (autosens_data) {
        inputs.autosens = autosens_data;
    }
    
    return trio_iobHistory.calcTempTreatments(inputs, zeroTempDuration);
}
