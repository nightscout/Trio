//для pumpprofile.json параметры: settings/settings.json settings/bg_targets.json settings/insulin_sensitivities.json settings/basal_profile.json preferences.json settings/carb_ratios.json settings/temptargets.json settings/model.json
//для profile.json параметры: settings/settings.json settings/bg_targets.json settings/insulin_sensitivities.json settings/basal_profile.json preferences.json settings/carb_ratios.json settings/temptargets.json settings/model.json settings/autotune.json

function generate(pumpsettings_data, bgtargets_data, isf_data, basalprofile_data, preferences_input = false, carbratio_input = false, temptargets_input = false, model_input = false, autotune_input = false, freeaps_data) {
    if (bgtargets_data.units !== 'mg/dL') {
        if (bgtargets_data.units === 'mmol/L') {
            for (var i = 0, len = bgtargets_data.targets.length; i < len; i++) {
                bgtargets_data.targets[i].high = bgtargets_data.targets[i].high * 18;
                bgtargets_data.targets[i].low = bgtargets_data.targets[i].low * 18;
            }
            bgtargets_data.units = 'mg/dL';
        } else {
            return { "error" : 'BG Target data is expected to be expressed in mg/dL or mmol/L. Found '+ bgtargets_data.units };
        }
    }
    
    if (isf_data.units !== 'mg/dL') {
        if (isf_data.units === 'mmol/L') {
            for (var i = 0, len = isf_data.sensitivities.length; i < len; i++) {
                isf_data.sensitivities[i].sensitivity = isf_data.sensitivities[i].sensitivity * 18;
            }
            isf_data.units = 'mg/dL';
        } else {
            return { "error" : 'ISF is expected to be expressed in mg/dL or mmol/L. Found '+ isf_data.units };
        }
    }

    var autotune_data = { };
    if (autotune_input) {
        autotune_data = autotune_input;
    }

    var temptargets_data = { };
    if (temptargets_input) {
        temptargets_data = temptargets_input;
    }
    
    var freeaps = { };
    if (freeaps_data) {
        freeaps = freeaps_data;
    }

    var model_data = { };
    if (model_input) {
        model_data = model_input.replace(/"/gi, '');
    }

    var carbratio_data = { };
    if (carbratio_input) {
        var errors = [ ];
        if (!(carbratio_input.schedule && carbratio_input.schedule[0].start && carbratio_input.schedule[0].ratio)) {
          errors.push("Carb ratio data should have an array called schedule with a start and ratio fields.");
        }
        if (carbratio_input.units !== 'grams' && carbratio_input.units !== 'exchanges')  {
          errors.push("Carb ratio should have units field set to 'grams' or 'exchanges'.");
        }
        if (errors.length) {
          return { "error" : errors.join(' ') };
        }
        carbratio_data = carbratio_input;
    }

    var preferences = { };
    if (preferences_input) {
        preferences = preferences_input;
        if (preferences.curve === "rapid-acting") {
            if (preferences.useCustomPeakTime) {
                preferences.insulinPeakTime =
                Math.max(50, Math.min(preferences.insulinPeakTime, 120));
            } else { preferences.insulinPeakTime = 75; }
        } 
        else if (preferences.curve === "ultra-rapid") {
            if (preferences.useCustomPeakTime) {
                preferences.insulinPeakTime =
                Math.max(35, Math.min(preferences.insulinPeakTime, 100));
            } else { preferences.insulinPeakTime = 55; }
        }
    }

    var inputs = { };
    //add all preferences to the inputs
    for (var pref in preferences) {
      if (preferences.hasOwnProperty(pref)) {
        inputs[pref] = preferences[pref];
      }
    }

    inputs.max_iob = inputs.max_iob || 0;
    //set these after to make sure nothing happens if they are also set in preferences
    inputs.settings = pumpsettings_data;
    inputs.targets = bgtargets_data;
    inputs.basals = basalprofile_data;
    inputs.isf = isf_data;
    inputs.carbratio = carbratio_data;
    inputs.temptargets = temptargets_data;
    inputs.model = model_data;
    inputs.autotune = autotune_data;

    if (autotune_data) {
        if (autotune_data.basalprofile) { inputs.basals = autotune_data.basalprofile; }
        if (!freeaps.onlyAutotuneBasals) {
            if (autotune_data.isfProfile) { inputs.isf = autotune_data.isfProfile; }
            if (autotune_data.carb_ratio) { inputs.carbratio.schedule[0].ratio = autotune_data.carb_ratio; }
        }
    }
    return freeaps_profile(inputs);
}
