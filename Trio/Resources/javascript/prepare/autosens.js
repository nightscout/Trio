// для settings/autosens.json параметры: monitor/glucose.json monitor/pumphistory-24h-zoned.json settings/basal_profile.json settings/profile.json monitor/carbhistory.json settings/temptargets.json

function generate(glucose_data, pumphistory_data, basalprofile, profile_data, carb_data = {}, temptarget_data = {}) {
    if (glucose_data.length < 72) {
        return { "ratio": 1, "error": "not enough glucose data to calculate autosens" };
    };
    
    var iob_inputs = {
        history: pumphistory_data,
        profile: profile_data
    };

    var detection_inputs = {
        iob_inputs: iob_inputs,
        carbs: carb_data,
        glucose_data: glucose_data,
        basalprofile: basalprofile,
        temptargets: temptarget_data
    };
    detection_inputs.deviations = 96;
    var ratio8h = freeaps_autosens(detection_inputs);
    detection_inputs.deviations = 288;
    var ratio24h = freeaps_autosens(detection_inputs);
    var lowestRatio = ratio8h.ratio < ratio24h.ratio ? ratio8h : ratio24h;
    return lowestRatio;
}
