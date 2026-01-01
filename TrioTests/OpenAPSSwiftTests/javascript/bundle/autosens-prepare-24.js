// для settings/autosens.json параметры: monitor/glucose.json monitor/pumphistory-24h-zoned.json settings/basal_profile.json settings/profile.json monitor/carbhistory.json settings/temptargets.json

function generate(glucose_data, pumphistory_data, basalprofile, profile_data, carb_data = {}, temptarget_data = {}, now = null) {
    if (glucose_data.length < 72) {
        return { "ratio": 1, "error": "not enough glucose data to calculate autosens" };
    };
    
    if (now) {
        now = new Date(now);
    } else {
        now = new Date();
    }
    
    var iob_inputs = {
        history: pumphistory_data,
        profile: profile_data,
        clock: now
    };

    var detection_inputs = {
        iob_inputs: iob_inputs,
        carbs: carb_data,
        glucose_data: glucose_data,
        basalprofile: basalprofile,
        temptargets: temptarget_data
    };
    
    // 24 hours only
    detection_inputs.deviations = 288;
    return trio_autosens(detection_inputs, now);
}

