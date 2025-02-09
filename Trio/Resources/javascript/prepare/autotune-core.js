function generate(prepped_glucose_data,previous_autotune_data,pumpprofile_data) {
  if (!pumpprofile_data.useCustomPeakTime) {
      previous_autotune_data.dia = pumpprofile_data.dia;
      previous_autotune_data.insulinPeakTime = pumpprofile_data.insulinPeakTime;
    };

    // Always keep the curve value up to date with what's in the user preferences
    previous_autotune_data.curve = pumpprofile_data.curve;

    inputs = {
        preppedGlucose: prepped_glucose_data
      , previousAutotune: previous_autotune_data
      , pumpProfile: pumpprofile_data
    };

    return freeaps_autotuneCore(inputs);
}
