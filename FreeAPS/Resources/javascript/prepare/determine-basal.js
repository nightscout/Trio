//для enact/smb-suggested.json параметры: monitor/iob.json monitor/temp_basal.json monitor/glucose.json settings/profile.json settings/autosens.json --meal monitor/meal.json --microbolus --reservoir monitor/reservoir.json

function generate(iob, currenttemp, glucose, profile, autosens = null, meal = null, microbolusAllowed = false, reservoir = null, clock = new Date(), pump_history, preferences, basalProfile, oref2_variables) {

    var clock = new Date();
    
    var middleware_was_used = "";
    try {
        var middlewareReason = middleware(iob, currenttemp, glucose, profile, autosens, meal, reservoir, clock, pump_history, preferences, basalProfile, oref2_variables);
        middleware_was_used = (middlewareReason || "Nothing changed");
        console.log("Middleware reason: " + middleware_was_used);
    } catch (error) {
        console.log("Invalid middleware: " + error);
    };

    var glucose_status = freeaps_glucoseGetLast(glucose);
    var autosens_data = null;

    if (autosens) {
        autosens_data = autosens;
    }
    
    var reservoir_data = null;
    if (reservoir) {
        reservoir_data = reservoir;
    }

    var meal_data = {};
    if (meal) {
        meal_data = meal;
    }
    
    var pumphistory = {};
    if (pump_history) {
        pumphistory = pump_history;
    }
    
    var basalprofile = {};
    if (basalProfile) {
        basalprofile = basalProfile;
    }
    
    var oref2_variables_ = {};
    if (oref2_variables) {
        oref2_variables_ = oref2_variables;
    }
    
    return freeaps_determineBasal(glucose_status, currenttemp, iob, profile, autosens_data, meal_data, freeaps_basalSetTemp, microbolusAllowed, reservoir_data, clock, pumphistory, preferences, basalprofile, oref2_variables_, middleware_was_used);
}
