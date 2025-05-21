/*
  Determine Basal
  Released under MIT license. See the accompanying LICENSE.txt file for
  full terms and conditions
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE.
*/

// Define various functions used later on, in the main function determine_basal() below

var round_basal = require('../round-basal');

// Rounds value to 'digits' decimal places
function round(value, digits) {
    if (! digits) { digits = 0; }
    var scale = Math.pow(10, digits);
    return Math.round(value * scale) / scale;
}

// we expect BG to rise or fall at the rate of BGI,
// adjusted by the rate at which BG would need to rise /
// fall to get eventualBG to target over 2 hours
function calculate_expected_delta(target_bg, eventual_bg, bgi) {
    // (hours * mins_per_hour) / 5 = how many 5 minute periods in 2h = 24
    var five_min_blocks = (2 * 60) / 5;
    var target_delta = target_bg - eventual_bg;
    return /* expectedDelta */ round(bgi + (target_delta / five_min_blocks), 1);
}


function convert_bg(value, profile)
{
    if (profile.out_units === "mmol/L")
    {
        return round(value * 0.0555,1);
    }
    else
    {
        return Math.round(value);
    }
}
function enable_smb(profile, microBolusAllowed, meal_data, bg, target_bg, high_bg, oref_variables, time) {
    if (oref_variables.smbIsScheduledOff){
        /* Below logic is related to profile overrides which can disable SMBs or disable them for a scheduled window.
         * SMBs will be disabled from [start, end), such that if an SMB is scheduled to be disabled from 10 AM to 2 PM,
         * an SMB will not be allowed from 10:00:00 until 1:59:59.
         */
        let currentHour = new Date(time.getHours());
        let startTime = oref_variables.start;
        let endTime = oref_variables.end;

        if (startTime < endTime && (currentHour >= startTime && currentHour < endTime)) {
            console.error("SMB disabled: current time is in SMB disabled scheduled")
            return false
        } else if (startTime > endTime && (currentHour >= startTime || currentHour < endTime)) {
            console.error("SMB disabled: current time is in SMB disabled scheduled")
            return false
        } else if (startTime == 0 && endTime == 0) {
            console.error("SMB disabled: current time is in SMB disabled scheduled")
            return false;
        } else if (startTime == endTime && currentHour == startTime) {
            console.error("SMB disabled: current time is in SMB disabled scheduled")
            return false;
        }
    }
    // disable SMB when a high temptarget is set
    if (! microBolusAllowed) {
        console.error("SMB disabled (!microBolusAllowed)");
        return false;
    } else if (! profile.allowSMB_with_high_temptarget && profile.temptargetSet && target_bg > 100) {
        console.error("SMB disabled due to high temptarget of " + target_bg);
        return false;
    } else if (meal_data.bwFound === true && profile.A52_risk_enable === false) {
        console.error("SMB disabled due to Bolus Wizard activity in the last 6 hours.");
        return false;
    // Disable if invalid CGM reading (HIGH)
    } else if (bg == 400) {
            console.error("Invalid CGM (HIGH). SMBs disabled.");
        return false;
    }

    // enable SMB/UAM if always-on (unless previously disabled for high temptarget)
    if (profile.enableSMB_always === true) {
        if (meal_data.bwFound) {
            console.error("Warning: SMB enabled within 6h of using Bolus Wizard: be sure to easy bolus 30s before using Bolus Wizard");
        } else {
            console.error("SMB enabled due to enableSMB_always");
        }
        return true;
    }

    // enable SMB/UAM (if enabled in preferences) while we have COB
    if (profile.enableSMB_with_COB === true && meal_data.mealCOB) {
        if (meal_data.bwCarbs) {
            console.error("Warning: SMB enabled with Bolus Wizard carbs: be sure to easy bolus 30s before using Bolus Wizard");
        } else {
            console.error("SMB enabled for COB of " + meal_data.mealCOB);
        }
        return true;
    }

    // enable SMB/UAM (if enabled in preferences) for a full 6 hours after any carb entry
    // (6 hours is defined in carbWindow in lib/meal/total.js)
    if (profile.enableSMB_after_carbs === true && meal_data.carbs ) {
        if (meal_data.bwCarbs) {
            console.error("Warning: SMB enabled with Bolus Wizard carbs: be sure to easy bolus 30s before using Bolus Wizard");
        } else {
            console.error("SMB enabled for 6h after carb entry");
        }
        return true;
    }

    // enable SMB/UAM (if enabled in preferences) if a low temptarget is set
    if (profile.enableSMB_with_temptarget === true && (profile.temptargetSet && target_bg < 100)) {
        if (meal_data.bwFound) {
            console.error("Warning: SMB enabled within 6h of using Bolus Wizard: be sure to easy bolus 30s before using Bolus Wizard");
        } else {
            console.error("SMB enabled for temptarget of " + convert_bg(target_bg, profile));
        }
        return true;
    }

    // enable SMB if high bg is found
    if (profile.enableSMB_high_bg === true && high_bg !== null && bg >= high_bg) {
        console.error("Checking BG to see if High for SMB enablement.");
        console.error("Current BG", bg, " | High BG ", high_bg);
        if (meal_data.bwFound) {
            console.error("Warning: High BG SMB enabled within 6h of using Bolus Wizard: be sure to easy bolus 30s before using Bolus Wizard");
        } else {
            console.error("High BG detected. Enabling SMB.");
        }
        return true;
    }

    console.error("SMB disabled (no enableSMB preferences active or no condition satisfied)");
    return false;
}


var determine_basal = function determine_basal(glucose_status, currenttemp, iob_data, profile, autosens_data, meal_data, tempBasalFunctions, microBolusAllowed, reservoir_data, currentTime, pumphistory, preferences, basalprofile, oref2_variables, middleWare) {

    var profileTarget = profile.min_bg;
    var overrideTarget = oref2_variables.overrideTarget;
    if (overrideTarget != 0 && overrideTarget != 6 && oref2_variables.useOverride && !profile.temptargetSet) {
        profileTarget = overrideTarget;
    }
    const smbIsOff = oref2_variables.smbIsOff;
    const advancedSettings = oref2_variables.advancedSettings;
    const isfAndCr = oref2_variables.isfAndCr;
    const isf = oref2_variables.isf;
    const cr_ = oref2_variables.cr;
    const smbMinutes = oref2_variables.smbMinutes;
    const uamMinutes = oref2_variables.uamMinutes;
    // tdd past 24 hour
    let tdd = oref2_variables.currentTDD;
    var logOutPut = "";
    var tddReason = "";

    var dynISFenabled = preferences.useNewFormula

    var insulinForManualBolus = 0;
    var manualBolusErrorString = 0;
    var threshold = profileTarget;

    var systemTime = new Date();
    if (currentTime) {
        systemTime = new Date(currentTime);
    }



    const weightedAverage = oref2_variables.weightedAverage;
    var overrideFactor = 1;
    var sensitivity = profile.sens;
    var carbRatio = profile.carb_ratio;
    if (oref2_variables.useOverride) {
        overrideFactor = oref2_variables.overridePercentage / 100;
        if (isfAndCr) {
            sensitivity /= overrideFactor;
            carbRatio /= overrideFactor;
        } else {
            if (cr_) { carbRatio /= overrideFactor; }
            if (isf) { sensitivity /= overrideFactor; }
        }
    }
    const weightPercentage = profile.weightPercentage;
    const average_total_data = oref2_variables.average_total_data;

    // In case the autosens.min/max limits are reversed:
    const minLimitChris = Math.min(profile.autosens_min, profile.autosens_max);
    const maxLimitChris = Math.max(profile.autosens_min, profile.autosens_max);

    // Turn off when autosens.min = autosens.max
    if (maxLimitChris == minLimitChris || maxLimitChris < 1 || minLimitChris > 1) {
        dynISFenabled = false;
        console.log("Dynamic ISF disabled due to current autosens settings");
    }

    // Dynamic ratios
    const BG = glucose_status.glucose;
    const adjustmentFactor = preferences.adjustmentFactor;
    const adjustmentFactorSigmoid = preferences.adjustmentFactorSigmoid;
    const enable_sigmoid = preferences.sigmoid;
    const currentMinTarget = profileTarget;
    var exerciseSetting = false;
    var log = "";
    var tdd24h_14d_Ratio = 1;
    var basal_ratio_log = "";


    if (average_total_data > 0) {
        tdd24h_14d_Ratio = weightedAverage / average_total_data;
    }

    // respect autosens_max/min for tdd24h_14d_Ratio, used to adjust basal similarly as autosens
    if (tdd24h_14d_Ratio > 1) {
        tdd24h_14d_Ratio = Math.min(tdd24h_14d_Ratio, profile.autosens_max);
        tdd24h_14d_Ratio = round(tdd24h_14d_Ratio,2);
        basal_ratio_log = "Basal adjustment with a 24 hour  to total average (up to 14 days of data) TDD ratio (limited by Autosens max setting). Basal Ratio: " + tdd24h_14d_Ratio + ". Upper limit = Autosens max (" + profile.autosens_max + ")";
    }
    else if (tdd24h_14d_Ratio < 1) {
        tdd24h_14d_Ratio = Math.max(tdd24h_14d_Ratio, profile.autosens_min);
        tdd24h_14d_Ratio = round(tdd24h_14d_Ratio,2);
        basal_ratio_log = "Basal adjustment with a 24 hour to  to total average (up to 14 days of data) TDD ratio (limited by Autosens min setting). Basal Ratio: " + tdd24h_14d_Ratio + ". Lower limit = Autosens min (" + profile.autosens_min + ")";
    }
    else {
        basal_ratio_log = "Basal adjusted with a 24 hour to total average (up to 14 days of data) TDD ratio: " + tdd24h_14d_Ratio;
    }

    basal_ratio_log = ", Basal ratio: " + tdd24h_14d_Ratio;

    // One of two exercise settings (they share the same purpose)

    if (profile.high_temptarget_raises_sensitivity || profile.exercise_mode) {
    exerciseSetting = true;
    }

    // Turn off Chris' formula when using a temp target >= 118 (6.5 mol/l) and if an exercise setting is enabled.
    if (currentMinTarget >= 118 && exerciseSetting) {
        dynISFenabled = false;
        log = "Dynamic ISF temporarily off due to a high temp target/exercising. Current min target: " + currentMinTarget;
    }

    var startLog = ", Dynamic ratios log: ";
    var afLog = ", AF: " + (enable_sigmoid ? adjustmentFactorSigmoid : adjustmentFactor);
    var bgLog = "BG: " + BG + " mg/dl (" + (BG * 0.0555).toPrecision(2) + " mmol/l)";
    var formula = "";
    var weightLog = "";

    // Insulin curve
    const curve = preferences.curve;
    const ipt = profile.insulinPeakTime;
    const ucpk = preferences.useCustomPeakTime;
    var insulinFactor = 55; // deafult (120-65)
    var insulinPA = 65; // default (Novorapid/Novolog)

    switch (curve) {
        case "rapid-acting":
            insulinPA = 65;
            break;
        case "ultra-rapid":
            insulinPA = 50;
            break;
    }

    if (ucpk) {
        insulinFactor = 120 - ipt;
        console.log("Custom insulinpeakTime set to :" + ipt + ", insulinFactor: " + insulinFactor);
    } else {
        insulinFactor = 120 - insulinPA;
        console.log("insulinFactor set to : " + insulinFactor);
    }

    // Use weighted TDD average
    tdd_before = tdd;
    if (weightPercentage < 1 && weightedAverage > 1) {
        tdd = weightedAverage;
        console.log("Using weighted TDD average: " + round(tdd,2) + " U, instead of past 24 h (" + round(tdd_before,2) + " U), weight: " + weightPercentage);
        weightLog = ", Weighted TDD: " + round(tdd,2) + " U";
    }

    // Modified Chris Wilson's' formula with added adjustmentFactor for tuning and use of the autosens.ratio:
    // var newRatio = profile.sens * adjustmentFactor * tdd * BG / 277700;
    //
    // New logarithmic formula : var newRatio = profile.sens * adjustmentFactor * tdd * ln(( BG/insulinFactor) + 1 )) / 1800
    //

    var sigmoidLog = ""

    if (dynISFenabled) {
        // Logarithmic
        if (!enable_sigmoid) {
            var newRatio = sensitivity * adjustmentFactor * tdd * Math.log(BG/insulinFactor+1) / 1800;
            formula = ", Logarithmic formula";
        }
        // Sigmoid
        else {
            const as_min = minLimitChris;
            const autosens_interval = maxLimitChris - as_min;
            //Blood glucose deviation from set target (the lower BG target) converted to mmol/l to fit current formula.
            const bg_dev = (BG - profileTarget) * 0.0555;
            // Account for TDD of insulin. Compare last 2 hours with total data (up to 14 days)
            var tdd_factor = tdd24h_14d_Ratio; // weighted average TDD / total data average TDD
            var max_minus_one = maxLimitChris - 1;
            // Avoid division by 0
            if (maxLimitChris == 1) {
                max_minus_one = maxLimitChris + 0.01 - 1;
            }
            //Makes sigmoid factor(y) = 1 when BG deviation(x) = 0.
            const fix_offset = (Math.log10(1/max_minus_one-as_min/max_minus_one) / Math.log10(Math.E));
            //Exponent used in sigmoid formula
            const exponent = bg_dev * adjustmentFactorSigmoid * tdd_factor + fix_offset;
            // The sigmoid function
            const sigmoid_factor = autosens_interval / (1 + Math.exp(-exponent)) + as_min;
            newRatio = sigmoid_factor;
            formula = ", Sigmoid function";
        }
    }

    var dynamicISFLog = "";
    var limitLog = "";

    if (dynISFenabled && tdd > 0) {

        dynamicISFLog = ", Dynamic ISF: On";

        // Respect autosens.max and autosens.min limitLogs
        if (newRatio > maxLimitChris) {
            log = ", Dynamic ISF limited by autosens_max setting: " + maxLimitChris + " (" +  round(newRatio,2) + "), ";
            limitLog = ", Autosens/Dynamic Limit: " + maxLimitChris + " (" +  round(newRatio,2) + ")";
            newRatio = maxLimitChris;
        } else if (newRatio < minLimitChris) {
            log = ", Dynamic ISF limited by autosens_min setting: " + minLimitChris + " (" +  round(newRatio,2) + "). ";
            limitLog = ", Autosens/Dynamic Limit: " + minLimitChris + " (" +  round(newRatio,2) + ")";
            newRatio = minLimitChris;
        }

        const isf = sensitivity / newRatio;

         // Set the new ratio
         autosens_data.ratio = newRatio;

        sigmoidLog = ". Using Sigmoid function, the autosens ratio has been adjusted with sigmoid factor to: " + round(autosens_data.ratio, 2) + ". New ISF = " + round(isf, 2) + " mg/dl (" + round(0.0555 * isf, 2) + " (mmol/l).";

        if (!enable_sigmoid) {
            log += ", Dynamic autosens.ratio set to " + round(newRatio,2) + " with ISF: " + isf.toPrecision(3) + " mg/dl/U (" + (isf * 0.0555).toPrecision(3) + " mmol/l/U)";
        } else { log += sigmoidLog }


        logOutPut += startLog + bgLog + afLog + formula + log + dynamicISFLog + weightLog;

    } else { logOutPut += startLog + "Dynamic Settings disabled"; }

    console.log(logOutPut);

    if (!dynISFenabled) {
        tddReason += "";
    } else if (dynISFenabled && profile.tddAdjBasal) {
        tddReason += dynamicISFLog + formula + limitLog + afLog + basal_ratio_log;
    }
    else if (dynISFenabled && !profile.tddAdjBasal) { tddReason += dynamicISFLog + formula + limitLog + afLog; }

    if (0.5 !== profile.smb_delivery_ratio) {
        tddReason += ", SMB Ratio: " + Math.min(profile.smb_delivery_ratio, 1);
    }

    // Not confident but something like this in iAPS v3.0.3
    if (middleWare !== "" && middleWare !== "Nothing changed"){
        tddReason += ", Middleware: " + middleWare;
    }

    // --------------- END OF DYNAMIC RATIOS CALCULATION  ------ A FEW LINES ADDED ALSO AT LINE NR 1136 and 1178 ------------------------------------------------


    // Set variables required for evaluating error conditions
    var rT = {}; //short for requestedTemp

    var deliverAt = new Date(systemTime);

    if (typeof profile === 'undefined' || typeof profile.current_basal === 'undefined') {
        rT.error ='Error: could not get current basal rate';
        return rT;
    }
    var profile_current_basal = round_basal(profile.current_basal, profile) * overrideFactor;
    var basal = profile_current_basal;

    // Print Current Override factor, if any
    if (oref2_variables.useOverride) {
        if (oref2_variables.duration == 0) {
            console.log("Profile Override is active. Override " + round(overrideFactor * 100, 0) + "%. Override Duration: " + "Enabled indefinitely");
        } else
            console.log("Profile Override is active. Override " + round(overrideFactor * 100, 0) + "%. Override Expires in: " + oref2_variables.duration + " min.");
    }

    var bgTime = new Date(glucose_status.date);
    var minAgo = round( (systemTime - bgTime) / 60 / 1000 ,1);

    var bg = glucose_status.glucose;
    var noise = glucose_status.noise;

// Prep various delta variables.
    var tick;

    if (glucose_status.delta > -0.5) {
        tick = "+" + round(glucose_status.delta,0);
    } else {
        tick = round(glucose_status.delta,0);
    }
    //var minDelta = Math.min(glucose_status.delta, glucose_status.short_avgdelta, glucose_status.long_avgdelta);
    var minDelta = Math.min(glucose_status.delta, glucose_status.short_avgdelta);
    var minAvgDelta = Math.min(glucose_status.short_avgdelta, glucose_status.long_avgdelta);
    var maxDelta = Math.max(glucose_status.delta, glucose_status.short_avgdelta, glucose_status.long_avgdelta);


// Cancel high temps (and replace with neutral) or shorten long zero temps for various error conditions

    // 38 is an xDrip error state that usually indicates sensor failure
    // all other BG values between 11 and 37 mg/dL reflect non-error-code BG values, so we should zero temp for those
// First, print out different explanations for each different error condition
    if (bg <= 10 || bg === 38 || noise >= 3) {  //Dexcom is in ??? mode or calibrating, or xDrip reports high noise
        rT.reason = "CGM is calibrating, in ??? state, or noise is high";
    }
    var tooflat=false;
    if (bg > 60 && glucose_status.delta == 0 && glucose_status.short_avgdelta > -1 && glucose_status.short_avgdelta < 1 && glucose_status.long_avgdelta > -1 && glucose_status.long_avgdelta < 1 && bg != 400) {
        if (glucose_status.device == "fakecgm") {
            console.error("CGM data is unchanged (" + convert_bg(bg,profile) + "+" + convert_bg(glucose_status.delta,profile)+ ") for 5m w/ " + convert_bg(glucose_status.short_avgdelta,profile) + " mg/dL ~15m change & " + convert_bg(glucose_status.long_avgdelta,2) + " mg/dL ~45m change");
            console.error("Simulator mode detected (" + glucose_status.device + "): continuing anyway");
        } else if (bg != 400) {
            tooflat=true;
        }
    }

    if (minAgo > 12 || minAgo < -5) { // Dexcom data is too old, or way in the future
        rT.reason = "If current system time " + systemTime + " is correct, then BG data is too old. The last BG data was read "+minAgo+"m ago at "+bgTime;

        // if BG is too old/noisy, or is completely unchanging, cancel any high temps and shorten any long zero temps
    } else if ( glucose_status.short_avgdelta === 0 && glucose_status.long_avgdelta === 0 && bg != 400 ) {
        if ( glucose_status.last_cal && glucose_status.last_cal < 3 ) {
            rT.reason = "CGM was just calibrated";
        } else {
            rT.reason = "CGM data is unchanged (" + convert_bg(bg,profile) + "+" + convert_bg(glucose_status.delta,profile) + ") for 5m w/ " + convert_bg(glucose_status.short_avgdelta,profile) + " mg/dL ~15m change & " + convert_bg(glucose_status.long_avgdelta,profile) + " mg/dL ~45m change";
        }
    }

    if (bg != 400) {
        if (bg <= 10 || bg === 38 || noise >= 3 || minAgo > 12 || minAgo < -5 || ( glucose_status.short_avgdelta === 0 && glucose_status.long_avgdelta === 0 ) ) {
            if (currenttemp.rate >= basal) { // high temp is running
                rT.reason += ". Canceling high temp basal of " + currenttemp.rate;
                rT.deliverAt = deliverAt;
                rT.temp = 'absolute';
                rT.duration = 0;
                rT.rate = 0;
                return rT;
                // don't use setTempBasal(), as it has logic that allows <120% high temps to continue running
                //return tempBasalFunctions.setTempBasal(basal, 30, profile, rT, currenttemp);
            } else if ( currenttemp.rate === 0 && currenttemp.duration > 30 ) { //shorten long zero temps to 30m
                rT.reason += ". Shortening " + currenttemp.duration + "m long zero temp to 30m. ";
                rT.deliverAt = deliverAt;
                rT.temp = 'absolute';
                rT.duration = 30;
                rT.rate = 0;
                return rT;
                // don't use setTempBasal(), as it has logic that allows long zero temps to continue running
                //return tempBasalFunctions.setTempBasal(0, 30, profile, rT, currenttemp);
            } else { //do nothing.
                rT.reason += ". Temp " + currenttemp.rate + " <= current basal " + basal + "U/hr; doing nothing. ";
                return rT;
            }
        }
    }


// Get configured target, and return if unable to do so.
// This should occur after checking that we're not in one of the CGM-data-related error conditions handled above,
// and before using target_bg to adjust sensitivityRatio below.
    var max_iob = profile.max_iob; // maximum amount of non-bolus IOB OpenAPS will ever deliver

    // if min and max are set, then set target to their average
    var target_bg;
    var min_bg;
    var max_bg;
    var high_bg;

    if (typeof profileTarget !== 'undefined') {
            min_bg = profileTarget;
    }
    if (typeof profile.max_bg !== 'undefined') {
            max_bg = profileTarget;
    }
    if (typeof profile.enableSMB_high_bg_target !== 'undefined') {
        high_bg = profile.enableSMB_high_bg_target;
    }
    if (typeof profileTarget !== 'undefined') {
        target_bg = profileTarget;

    } else {
        rT.error ='Error: could not determine target_bg. ';
        return rT;
    }


// Calculate sensitivityRatio based on temp targets, if applicable, or using the value calculated by autosens
//    var sensitivityRatio;
    var high_temptarget_raises_sensitivity = profile.exercise_mode || profile.high_temptarget_raises_sensitivity;
    var normalTarget = 100; // evaluate high/low temptarget against 100, not scheduled target (which might change)
    var halfBasalTarget = 160;  // when temptarget is 160 mg/dL, run 50% basal (120 = 75%; 140 = 60%)
    // 80 mg/dL with low_temptarget_lowers_sensitivity would give 1.5x basal, but is limitLoged to autosens_max (1.2x by default)
    //if ( profile.half_basal_exercise_target ) {
    halfBasalTarget = profile.half_basal_exercise_target;
    //}

    if ( high_temptarget_raises_sensitivity && profile.temptargetSet && target_bg > normalTarget ||
        profile.low_temptarget_lowers_sensitivity && profile.temptargetSet && target_bg < normalTarget ) {
        // w/ target 100, temp target 110 = .89, 120 = 0.8, 140 = 0.67, 160 = .57, and 200 = .44
        // e.g.: Sensitivity ratio set to 0.8 based on temp target of 120; Adjusting basal from 1.65 to 1.35; ISF from 58.9 to 73.6
        //sensitivityRatio = 2/(2+(target_bg-normalTarget)/40);
        var c = halfBasalTarget - normalTarget;
        // getting multiplication less or equal to 0 means that we have a really low target with a really low halfBasalTarget
        // with low TT and lowTTlowersSensitivity we need autosens_max as a value
        // we use multiplication instead of the division to avoid "division by zero error"
        if (c * (c + target_bg-normalTarget) <= 0.0) {
          sensitivityRatio = profile.autosens_max;
        }
        else {
          sensitivityRatio = c/(c+target_bg-normalTarget);
        }
        // limit sensitivityRatio to profile.autosens_max (1.2x by default)
        sensitivityRatio = Math.min(sensitivityRatio, profile.autosens_max);
        sensitivityRatio = round(sensitivityRatio,2);
        process.stderr.write("Sensitivity ratio set to "+sensitivityRatio+" based on temp target of "+target_bg+"; ");
    }
    else if (typeof autosens_data !== 'undefined' && autosens_data) {
        sensitivityRatio = autosens_data.ratio;

        // Override Profile.Target
    if (overrideTarget !== 0 && overrideTarget !== 6 && overrideTarget !== profile.min_bg && !profile.temptargetSet) {
        target_bg = overrideTarget;
        console.log("Current Override Profile Target: " + convert_bg(overrideTarget, profile) + " " + profile.out_units);
    }
        process.stderr.write("Autosens ratio: "+sensitivityRatio+"; ");
    }

    // Increase the dynamic ratio when using a low temp target
    if (profile.temptargetSet && target_bg < normalTarget && dynISFenabled && BG >= target_bg) {
        if (sensitivityRatio < newRatio) {
            autosens_data.ratio = newRatio * (normalTarget/target_bg);
            //Use autosesns.max limit
            autosens_data.ratio = Math.min(autosens_data.ratio, profile.autosens_max);
            sensitivityRatio = round(autosens_data.ratio, 2);
            console.log("Dynamic ratio increased from " + round(newRatio, 2) + " to " + round(autosens_data.ratio,2) + " due to a low temp target (" + target_bg + ").");
        }
    }

    if (sensitivityRatio && !dynISFenabled) { // Only enable adjustment of basal by sensitivityRatio when not using dISF
        basal = profile.current_basal * overrideFactor * sensitivityRatio;
        basal = round_basal(basal, profile);
        if (basal !== profile_current_basal) {
            process.stderr.write("Adjusting basal from "+profile_current_basal+" to "+basal+"; ");
        } else {
            process.stderr.write("Basal unchanged: "+basal+"; ");
        }
    }

    else if (dynISFenabled && profile.tddAdjBasal) {
        basal = profile.current_basal * tdd24h_14d_Ratio * overrideFactor;
        basal = round_basal(basal, profile);
        if (average_total_data > 0) {
            process.stderr.write("TDD-adjustment of basals activated, using tdd24h_14d_Ratio " + round(tdd24h_14d_Ratio,2) + ", TDD 24h = " + round(tdd_before,2) + "U, Weighted average TDD = " + round(weightedAverage,2) + "U, (Weight percentage = " + weightPercentage + "), Total data of TDDs (up to 14 days) average = " + round(average_total_data,2) + "U. " );
            if (basal !== profile_current_basal * overrideFactor) {
                process.stderr.write("Adjusting basal from " + profile_current_basal * overrideFactor + " U/h to " + basal + " U/h; ");
            } else { process.stderr.write("Basal unchanged: " + basal + " U/h; "); }
        }
    }

// Conversely, adjust BG target based on autosens ratio if no temp target is running
    // adjust min, max, and target BG for sensitivity, such that 50% increase in ISF raises target from 100 to 120
    if (profile.temptargetSet) {
        //process.stderr.write("Temp Target set, not adjusting with autosens; ");
    } else if (typeof autosens_data !== 'undefined' && autosens_data) {
        if ( profile.sensitivity_raises_target && autosens_data.ratio < 1 || profile.resistance_lowers_target && autosens_data.ratio > 1 ) {
            // with a target of 100, default 0.7-1.2 autosens min/max range would allow a 93-117 target range
            min_bg = round((min_bg - 60) / autosens_data.ratio) + 60;
            max_bg = round((max_bg - 60) / autosens_data.ratio) + 60;
            var new_target_bg = round((target_bg - 60) / autosens_data.ratio) + 60;
            // don't allow target_bg below 80
            new_target_bg = Math.max(80, new_target_bg);
            if (target_bg === new_target_bg) {
                process.stderr.write("target_bg unchanged: " + convert_bg(new_target_bg, profile) + "; ");
            } else {
                process.stderr.write("target_bg from "+ convert_bg(new_target_bg, profile) + " to " + convert_bg(new_target_bg, profile) + "; ");
            }
            target_bg = new_target_bg;
        }
    }

    // Display if differing in enacted box
    var targetLog = convert_bg(target_bg, profile);
    if  (target_bg != profileTarget) {
        if (overrideTarget !== 0 && overrideTarget !== 6 && overrideTarget !== target_bg) {
            targetLog = convert_bg(profileTarget, profile) + "\u2192" + convert_bg(overrideTarget, profile) + "\u2192" + convert_bg(target_bg, profile);
        } else {
            targetLog = convert_bg(profileTarget, profile) + "\u2192" + convert_bg(target_bg, profile);
        }
    }

    // Raise target for noisy / raw CGM data.
    var adjustedMinBG = 200;
    var adjustedTargetBG = 200;
    var adjustedMaxBG = 200;
    if (glucose_status.noise >= 2) {
        // increase target at least 10% (default 30%) for raw / noisy data
        var noisyCGMTargetMultiplier = Math.max( 1.1, profile.noisyCGMTargetMultiplier );
        // don't allow maxRaw above 250
        var maxRaw = Math.min( 250, profile.maxRaw );
        adjustedMinBG = round(Math.min(200, min_bg * noisyCGMTargetMultiplier ));
        adjustedTargetBG = round(Math.min(200, target_bg * noisyCGMTargetMultiplier ));
        adjustedMaxBG = round(Math.min(200, max_bg * noisyCGMTargetMultiplier ));
        process.stderr.write("Raising target_bg for noisy / raw CGM data, from " + convert_bg(new_target_bg, profile) + " to " + convert_bg(adjustedTargetBG, profile) + "; ");
        min_bg = adjustedMinBG;
        target_bg = adjustedTargetBG;
        max_bg = adjustedMaxBG;
    }

    // min_bg thresholds: 80->60, 90->65, 100->70, 110->75, 120->80
    threshold = min_bg - 0.5*(min_bg-40);
    // Set threshold to the user's setting, as long as it's between 60-120 and above the default calculated threshold
    threshold = Math.min(Math.max(profile.threshold_setting, threshold, 60), 120);
    console.error(`Threshold set to ${convert_bg(threshold, profile)}`);

// If iob_data or its required properties are missing, return.
// This has to be checked after checking that we're not in one of the CGM-data-related error conditions handled above,
// and before attempting to use iob_data below.

// Adjust ISF based on sensitivityRatio
    var isfreason = ""
    var profile_sens = round(sensitivity,1);
    var sens = sensitivity;
    if (typeof autosens_data !== 'undefined' && autosens_data) {
        sens = sensitivity / sensitivityRatio;
        sens = round(sens, 1);
        if (sens !== sensitivity) {
            process.stderr.write("ISF from "+ convert_bg(sensitivity,profile) +" to " + convert_bg(sens,profile));
        } else {
            process.stderr.write("ISF unchanged: "+ convert_bg(sens,profile));
        }
        //process.stderr.write(" (autosens ratio "+sensitivityRatio+")");
        isfreason += "Autosens ratio: " + round(sensitivityRatio, 2) + ", ISF: " + convert_bg(sensitivity,profile) + "\u2192" + convert_bg(sens,profile);

    }
    console.error("CR:" + carbRatio);

    if (typeof iob_data === 'undefined' ) {
        rT.error ='Error: iob_data undefined. ';
        return rT;
    }

    var iobArray = iob_data;

    if (typeof(iob_data.length) && iob_data.length > 1) {
        iob_data = iobArray[0];
    }

    if (typeof iob_data.activity === 'undefined' || typeof iob_data.iob === 'undefined' ) {
        rT.error ='Error: iob_data missing some property. ';
        return rT;
    }

// Compare currenttemp to iob_data.lastTemp and cancel temp if they don't match, as a safety check
// This should occur after checking that we're not in one of the CGM-data-related error conditions handled above,
// and before returning (doing nothing) below if eventualBG is undefined.
    var lastTempAge;
    if (typeof iob_data.lastTemp !== 'undefined' ) {
        lastTempAge = round(( new Date(systemTime).getTime() - iob_data.lastTemp.date ) / 60000); // in minutes
    } else {
        lastTempAge = 0;
    }
    //console.error("currenttemp:",currenttemp,"lastTemp:",JSON.stringify(iob_data.lastTemp),"lastTempAge:",lastTempAge,"m");
    var tempModulus = (lastTempAge + currenttemp.duration) % 30;
    console.error("currenttemp:" + currenttemp.rate + " lastTempAge:" + lastTempAge + "m, tempModulus:" + tempModulus + "m");
    rT.temp = 'absolute';
    rT.deliverAt = deliverAt;
    if ( microBolusAllowed && currenttemp && iob_data.lastTemp && currenttemp.rate !== iob_data.lastTemp.rate && lastTempAge > 10 && currenttemp.duration ) {
        rT.reason = "Warning: currenttemp rate " + currenttemp.rate + " != lastTemp rate " + iob_data.lastTemp.rate + " from pumphistory; canceling temp"; // reason.conclusion started
        return tempBasalFunctions.setTempBasal(0, 0, profile, rT, currenttemp);
    }
    if ( currenttemp && iob_data.lastTemp && currenttemp.duration > 0 ) {
        //console.error(lastTempAge, round(iob_data.lastTemp.duration,1), round(lastTempAge - iob_data.lastTemp.duration,1));
        var lastTempEnded = lastTempAge - iob_data.lastTemp.duration;
        if ( lastTempEnded > 5 && lastTempAge > 10 ) {
            rT.reason = "Warning: currenttemp running but lastTemp from pumphistory ended " + lastTempEnded + "m ago; canceling temp"; // reason.conclusion started
            //console.error(currenttemp, round(iob_data.lastTemp,1), round(lastTempAge,1));
            return tempBasalFunctions.setTempBasal(0, 0, profile, rT, currenttemp);
        }
    }

// Calculate BGI, deviation, and eventualBG.
// This has to happen after we obtain iob_data

    //calculate BG impact: the amount BG "should" be rising or falling based on insulin activity alone
    var bgi = round(( -iob_data.activity * sens * 5 ), 2);
    // project deviations for 30 minutes
    var deviation = round( 30 / 5 * ( minDelta - bgi ) );
    // don't overreact to a big negative delta: use minAvgDelta if deviation is negative
    if (deviation < 0) {
        deviation = round( (30 / 5) * ( minAvgDelta - bgi ) );
        // and if deviation is still negative, use long_avgdelta
        if (deviation < 0) {
            deviation = round( (30 / 5) * ( glucose_status.long_avgdelta - bgi ) );
        }
    }

    // calculate the naive (bolus calculator math) eventual BG based on net IOB and sensitivity
    var naive_eventualBG = bg;
    if (iob_data.iob > 0) {
        naive_eventualBG = round( bg - (iob_data.iob * sens) );
    } else { // if IOB is negative, be more conservative and use the lower of sens, profile.sens
        naive_eventualBG = round( bg - (iob_data.iob * Math.min(sens, sensitivity) ) );
    }
    // and adjust it for the deviation above
    var eventualBG = naive_eventualBG + deviation;

    if (typeof eventualBG === 'undefined' || isNaN(eventualBG)) {
        rT.error ='Error: could not calculate eventualBG. Sensitivity: ' + sens + ' Deviation: ' + deviation;
        return rT;
    }
    var expectedDelta = calculate_expected_delta(target_bg, eventualBG, bgi);
    var minPredBG;
    var minGuardBG;



    //console.error(reservoir_data);

// Initialize rT (requestedTemp) object. Has to be done after eventualBG is calculated.
    rT = {
        'temp': 'absolute'
        , 'bg': bg
        , 'tick': tick
        , 'eventualBG': eventualBG
        , 'insulinReq': 0
        , 'reservoir' : reservoir_data // The expected reservoir volume at which to deliver the microbolus (the reservoir volume from right before the last pumphistory run)
        , 'deliverAt' : deliverAt // The time at which the microbolus should be delivered
        , 'sensitivityRatio' : sensitivityRatio
        , 'CR' : round(carbRatio, 1)
        , 'current_target': target_bg
        , 'insulinForManualBolus': insulinForManualBolus
        , 'manualBolusErrorString': manualBolusErrorString
        , 'minDelta':  minDelta
        , 'expectedDelta':  expectedDelta
        , 'minGuardBG':  minGuardBG
        , 'minPredBG':  minPredBG
        , 'threshold': convert_bg(threshold, profile)
    };

// Generate predicted future BGs based on IOB, COB, and current absorption rate

// Initialize and calculate variables used for predicting BGs
    var COBpredBGs = [];
    var IOBpredBGs = [];
    var UAMpredBGs = [];
    var ZTpredBGs = [];
    COBpredBGs.push(bg);
    IOBpredBGs.push(bg);
    ZTpredBGs.push(bg);
    UAMpredBGs.push(bg);
    let enableSMB = false;

    // If SMB is always off, don't bother checking if we should enable SMBs
    if (smbIsOff) {
        console.error("SMBs are always off.");
        enableSMB = false;
    } else {
        enableSMB = enable_smb(
            profile,
            microBolusAllowed,
            meal_data,
            bg,
            target_bg,
            high_bg,
            oref2_variables,
            systemTime
        );
    }

    var enableUAM = (profile.enableUAM);

    //console.error(meal_data);
    // carb impact and duration are 0 unless changed below
    var ci = 0;
    var cid = 0;
    // calculate current carb absorption rate, and how long to absorb all carbs
    // CI = current carb impact on BG in mg/dL/5m
    ci = round((minDelta - bgi),1);
    var uci = round((minDelta - bgi),1);
    // ISF (mg/dL/U) / CR (g/U) = CSF (mg/dL/g)

    // use autosens-adjusted sens to counteract autosens meal insulin dosing adjustments so that
    // autotuned CR is still in effect even when basals and ISF are being adjusted by TT or autosens
    // this avoids overdosing insulin for large meals when low temp targets are active
    csf = sens / carbRatio;
    console.error("profile.sens:" + convert_bg(sensitivity,profile) + ", sens:" + convert_bg(sens,profile) + ", CSF:" + round(csf,1));

    var maxCarbAbsorptionRate = 30; // g/h; maximum rate to assume carbs will absorb if no CI observed
    // limitLog Carb Impact to maxCarbAbsorptionRate * csf in mg/dL per 5m
    var maxCI = round(maxCarbAbsorptionRate*csf*5/60,1);
    if (ci > maxCI) {
        console.error("Limiting carb impact from " + ci + " to " + maxCI + "mg/dL/5m (" + maxCarbAbsorptionRate + "g/h)");
        ci = maxCI;
    }
    var remainingCATimeMin = 3; // h; minimum duration of expected not-yet-observed carb absorption
    // adjust remainingCATime (instead of CR) for autosens if sensitivityRatio defined
    if (sensitivityRatio) {
        remainingCATimeMin = remainingCATimeMin / sensitivityRatio;
    }
    // 20 g/h means that anything <= 60g will get a remainingCATimeMin, 80g will get 4h, and 120g 6h
    // when actual absorption ramps up it will take over from remainingCATime
    var assumedCarbAbsorptionRate = 20; // g/h; maximum rate to assume carbs will absorb if no CI observed
    var remainingCATime = remainingCATimeMin;
    if (meal_data.carbs) {
        // if carbs * assumedCarbAbsorptionRate > remainingCATimeMin, raise it
        // so <= 90g is assumed to take 3h, and 120g=4h
        remainingCATimeMin = Math.max(remainingCATimeMin, meal_data.mealCOB/assumedCarbAbsorptionRate);
        var lastCarbAge = round(( new Date(systemTime).getTime() - meal_data.lastCarbTime ) / 60000);
        //console.error(meal_data.lastCarbTime, lastCarbAge);

        var fractionCOBAbsorbed = ( meal_data.carbs - meal_data.mealCOB ) / meal_data.carbs;
        // if the lastCarbTime was 1h ago, increase remainingCATime by 1.5 hours
        remainingCATime = remainingCATimeMin + 1.5 * lastCarbAge/60;
        remainingCATime = round(remainingCATime,1);
        //console.error(fractionCOBAbsorbed, remainingCATimeAdjustment, remainingCATime)
        console.error("Last carbs " + lastCarbAge + " minutes ago; remainingCATime:" + remainingCATime + "hours; " + round(fractionCOBAbsorbed*100, 1) + "% carbs absorbed");
    }

    // calculate the number of carbs absorbed over remainingCATime hours at current CI
    // CI (mg/dL/5m) * (5m)/5 (m) * 60 (min/hr) * 4 (h) / 2 (linear decay factor) = total carb impact (mg/dL)
    var totalCI = Math.max(0, ci / 5 * 60 * remainingCATime / 2);
    // totalCI (mg/dL) / CSF (mg/dL/g) = total carbs absorbed (g)
    var totalCA = totalCI / csf;
    var remainingCarbsCap = 90; // default to 90
    var remainingCarbsFraction = 1;
    if (profile.remainingCarbsCap) { remainingCarbsCap = Math.min(90,profile.remainingCarbsCap); }
    if (profile.remainingCarbsFraction) { remainingCarbsFraction = Math.min(1,profile.remainingCarbsFraction); }
    var remainingCarbsIgnore = 1 - remainingCarbsFraction;
    var remainingCarbs = Math.max(0, meal_data.mealCOB - totalCA - meal_data.carbs*remainingCarbsIgnore);
    remainingCarbs = Math.min(remainingCarbsCap,remainingCarbs);
    // assume remainingCarbs will absorb in a /\ shaped bilinear curve
    // peaking at remainingCATime / 2 and ending at remainingCATime hours
    // area of the /\ triangle is the same as a remainingCIpeak-height rectangle out to remainingCATime/2
    // remainingCIpeak (mg/dL/5m) = remainingCarbs (g) * CSF (mg/dL/g) * 5 (m/5m) * 1h/60m / (remainingCATime/2) (h)
    var remainingCIpeak = remainingCarbs * csf * 5 / 60 / (remainingCATime/2);
    //console.error(profile.min_5m_carbimpact,ci,totalCI,totalCA,remainingCarbs,remainingCI,remainingCATime);

    // calculate peak deviation in last hour, and slope from that to current deviation
    var slopeFromMaxDeviation = round(meal_data.slopeFromMaxDeviation,2);
    // calculate lowest deviation in last hour, and slope from that to current deviation
    var slopeFromMinDeviation = round(meal_data.slopeFromMinDeviation,2);
    // assume deviations will drop back down at least at 1/3 the rate they ramped up
    var slopeFromDeviations = Math.min(slopeFromMaxDeviation,-slopeFromMinDeviation/3);
    //console.error(slopeFromMaxDeviation);

    //5m data points = g * (1U/10g) * (40mg/dL/1U) / (mg/dL/5m)
    // duration (in 5m data points) = COB (g) * CSF (mg/dL/g) / ci (mg/dL/5m)
    // limitLog cid to remainingCATime hours: the reset goes to remainingCI
    var nfcid = 0;
    if (ci === 0) {
        // avoid divide by zero
        cid = 0;
    } else { cid = Math.min(remainingCATime*60/5/2,Math.max(0, meal_data.mealCOB * csf / ci )); }

    // duration (hours) = duration (5m) * 5 / 60 * 2 (to account for linear decay)
    console.error("Carb Impact:" + ci + "mg/dL per 5m; CI Duration:" + round(cid*5/60*2,1) + "hours; remaining CI (" + remainingCATime/2 + "h peak):" + round(remainingCIpeak,1) + "mg/dL per 5m");

    var minIOBPredBG = 999;
    var minCOBPredBG = 999;
    var minUAMPredBG = 999;
    //minGuardBG = bg;
    var minCOBGuardBG = 999;
    var minUAMGuardBG = 999;
    var minIOBGuardBG = 999;
    var minZTGuardBG = 999;
    var minPredBG;
    var avgPredBG;
    var IOBpredBG = eventualBG;
    var maxIOBPredBG = bg;
    var maxCOBPredBG = bg;
    var maxUAMPredBG = bg;
    var eventualPredBG = bg;
    var lastIOBpredBG;
    var lastCOBpredBG;
    var lastUAMpredBG;
    var lastZTpredBG;
    var UAMduration = 0;
    var remainingCItotal = 0;
    var remainingCIs = [];
    var predCIs = [];
    try {
        iobArray.forEach(function(iobTick) {
            //console.error(iobTick);
            var predBGI = round(( -iobTick.activity * sens * 5 ), 2);
            var predZTBGI = round(( -iobTick.iobWithZeroTemp.activity * sens * 5 ), 2);
            var ZTpredBG = naive_eventualBG;

            // for IOBpredBGs, predicted deviation impact drops linearly from current deviation down to zero
            // over 60 minutes (data points every 5m)
            var predDev = ci * ( 1 - Math.min(1,IOBpredBGs.length/(60/5)) );

            // Adding dynamic ISF in predictions for ZT and IOB. Modification from Tim Street's AAPS but with default as off:
            switch(true) {
                case dynISFenabled && !enable_sigmoid:
                    //IOBpredBG = IOBpredBGs[IOBpredBGs.length-1] + predBGI + predDev; // Adding dynamic ISF in predictions for UAM, ZT and IOB:
                    IOBpredBG = IOBpredBGs[IOBpredBGs.length-1] + (round(( -iobTick.activity * (1800 / ( tdd * adjustmentFactor * (Math.log((Math.max( IOBpredBGs[IOBpredBGs.length-1],39) / insulinFactor ) + 1 ) ) )) * 5 ),2)) + predDev;
                    //var ZTpredBG = ZTpredBGs[ZTpredBGs.length-1] + predZTBGI; // Adding dynamic ISF in predictions for UAM, ZT and IOB:
                    ZTpredBG = ZTpredBGs[ZTpredBGs.length-1] + (round(( -iobTick.iobWithZeroTemp.activity * (1800 / ( tdd * adjustmentFactor * (Math.log(( Math.max(ZTpredBGs[ZTpredBGs.length-1],39) / insulinFactor ) + 1 ) ) )) * 5 ), 2));
                    console.log("Dynamic ISF (Logarithmic Formula) )adjusted predictions for IOB and ZT: IOBpredBG: " + round(IOBpredBG,2) + " , ZTpredBG: " + round(ZTpredBG,2));
                    break;
                default:
                    IOBpredBG = IOBpredBGs[IOBpredBGs.length-1] + predBGI + predDev;
                    // calculate predBGs with long zero temp without deviations
                    ZTpredBG = ZTpredBGs[ZTpredBGs.length-1] + predZTBGI;
            }

            // for COBpredBGs, predicted carb impact drops linearly from current carb impact down to zero
            // eventually accounting for all carbs (if they can be absorbed over DIA)
            var predCI = Math.max(0, Math.max(0,ci) * ( 1 - COBpredBGs.length/Math.max(cid*2,1) ) );
            // if any carbs aren't absorbed after remainingCATime hours, assume they'll absorb in a /\ shaped
            // bilinear curve peaking at remainingCIpeak at remainingCATime/2 hours (remainingCATime/2*12 * 5m)
            // and ending at remainingCATime h (remainingCATime*12 * 5m intervals)
            var intervals = Math.min( COBpredBGs.length, (remainingCATime*12)-COBpredBGs.length );
            var remainingCI = Math.max(0, intervals / (remainingCATime/2*12) * remainingCIpeak );
            remainingCItotal += predCI+remainingCI;
            remainingCIs.push(round(remainingCI,0));
            predCIs.push(round(predCI,0));
            //process.stderr.write(round(predCI,1)+"+"+round(remainingCI,1)+" ");
            COBpredBG = COBpredBGs[COBpredBGs.length-1] + predBGI + Math.min(0,predDev) + predCI + remainingCI;
            // for UAMpredBGs, predicted carb impact drops at slopeFromDeviations
            // calculate predicted CI from UAM based on slopeFromDeviations
            var predUCIslope = Math.max(0, uci + ( UAMpredBGs.length*slopeFromDeviations ) );
            // if slopeFromDeviations is too flat, predicted deviation impact drops linearly from
            // current deviation down to zero over 3h (data points every 5m)
            var predUCImax = Math.max(0, uci * ( 1 - UAMpredBGs.length/Math.max(3*60/5,1) ) );
            //console.error(predUCIslope, predUCImax);
            // predicted CI from UAM is the lesser of CI based on deviationSlope or DIA
            var predUCI = Math.min(predUCIslope, predUCImax);
            if(predUCI>0) {
                //console.error(UAMpredBGs.length,slopeFromDeviations, predUCI);
                UAMduration=round((UAMpredBGs.length+1)*5/60,1);
            }

            // Adding dynamic ISF in predictions for UAM. Modification from Tim Street's AAPS but with default as off:
            switch(true) {
                case dynISFenabled && !enable_sigmoid:
                    //UAMpredBG = UAMpredBGs[UAMpredBGs.length-1] + predBGI + Math.min(0, predDev) + predUCI; // Adding dynamic ISF in predictions for UAM:
                    UAMpredBG = UAMpredBGs[UAMpredBGs.length-1] + (round(( -iobTick.activity * (1800 / ( tdd * adjustmentFactor * (Math.log(( Math.max(UAMpredBGs[UAMpredBGs.length-1],39) / insulinFactor ) + 1 ) ) )) * 5 ),2)) + Math.min(0, predDev) + predUCI;
                    console.log("Dynamic ISF (Logarithmic Formula) adjusted prediction for UAM: UAMpredBG: " + round(UAMpredBG,2));
                    break;
                default:
                    UAMpredBG = UAMpredBGs[UAMpredBGs.length-1] + predBGI + Math.min(0, predDev) + predUCI;
            }
            //console.error(predBGI, predCI, predUCI);
            // truncate all BG predictions at 4 hours
            if ( IOBpredBGs.length < 48 ) { IOBpredBGs.push(IOBpredBG); }
            if ( COBpredBGs.length < 48 ) { COBpredBGs.push(COBpredBG); }
            if ( UAMpredBGs.length < 48 ) { UAMpredBGs.push(UAMpredBG); }
            if ( ZTpredBGs.length < 48 ) { ZTpredBGs.push(ZTpredBG); }
            // calculate minGuardBGs without a wait from COB, UAM, IOB predBGs
            if ( COBpredBG < minCOBGuardBG ) { minCOBGuardBG = round(COBpredBG); }
            if ( UAMpredBG < minUAMGuardBG ) { minUAMGuardBG = round(UAMpredBG); }
            if ( IOBpredBG < minIOBGuardBG ) { minIOBGuardBG = round(IOBpredBG); }
            if ( ZTpredBG < minZTGuardBG ) { minZTGuardBG = round(ZTpredBG); }

            // set minPredBGs starting when currently-dosed insulin activity will peak
            // look ahead 60m (regardless of insulin type) so as to be less aggressive on slower insulins
            var insulinPeakTime = 60;
            // add 30m to allow for insulin delivery (SMBs or temps)
            insulinPeakTime = 90;
            var insulinPeak5m = (insulinPeakTime/60)*12;
            //console.error(insulinPeakTime, insulinPeak5m, profile.insulinPeakTime, profile.curve);

            // wait 90m before setting minIOBPredBG
            if ( IOBpredBGs.length > insulinPeak5m && (IOBpredBG < minIOBPredBG) ) { minIOBPredBG = round(IOBpredBG); }
            if ( IOBpredBG > maxIOBPredBG ) { maxIOBPredBG = IOBpredBG; }
            // wait 85-105m before setting COB and 60m for UAM minPredBGs
            if ( (cid || remainingCIpeak > 0) && COBpredBGs.length > insulinPeak5m && (COBpredBG < minCOBPredBG) ) { minCOBPredBG = round(COBpredBG); }
            if ( (cid || remainingCIpeak > 0) && COBpredBG > maxIOBPredBG ) { maxCOBPredBG = COBpredBG; }
            if ( enableUAM && UAMpredBGs.length > 12 && (UAMpredBG < minUAMPredBG) ) { minUAMPredBG = round(UAMpredBG); }
            if ( enableUAM && UAMpredBG > maxIOBPredBG ) { maxUAMPredBG = UAMpredBG; }
        });
        // set eventualBG to include effect of carbs
        //console.error("PredBGs:",JSON.stringify(predBGs));
    } catch (e) {
        console.error("Problem with iobArray.  Optional feature Advanced Meal Assist disabled");
    }
    if (meal_data.mealCOB) {
        console.error("predCIs (mg/dL/5m):" + predCIs.join(" "));
        console.error("remainingCIs:      " + remainingCIs.join(" "));
    }
    rT.predBGs = {};
    IOBpredBGs.forEach(function(p, i, theArray) {
        theArray[i] = round(Math.min(401,Math.max(39,p)));
    });
    for (var i=IOBpredBGs.length-1; i > 12; i--) {

        if (IOBpredBGs[i-1] !== IOBpredBGs[i]) { break; }
        else { IOBpredBGs.pop(); }
    }
    rT.predBGs.IOB = IOBpredBGs;
    lastIOBpredBG=round(IOBpredBGs[IOBpredBGs.length-1]);
    ZTpredBGs.forEach(function(p, i, theArray) {
        theArray[i] = round(Math.min(401,Math.max(39,p)));
    });
    for (i=ZTpredBGs.length-1; i > 6; i--) {
        // stop displaying ZTpredBGs once they're rising and above target
        if (ZTpredBGs[i-1] >= ZTpredBGs[i] || ZTpredBGs[i] <= target_bg) { break; }
        else { ZTpredBGs.pop(); }
    }
    rT.predBGs.ZT = ZTpredBGs;
    lastZTpredBG=round(ZTpredBGs[ZTpredBGs.length-1]);
    if (meal_data.mealCOB > 0 && ( ci > 0 || remainingCIpeak > 0 )) {
        COBpredBGs.forEach(function(p, i, theArray) {
            theArray[i] = round(Math.min(1500,Math.max(39,p)));
        });
        for (i=COBpredBGs.length-1; i > 12; i--) {
            if (COBpredBGs[i-1] !== COBpredBGs[i]) { break; }
            else { COBpredBGs.pop(); }
        }
        rT.predBGs.COB = COBpredBGs;
        lastCOBpredBG=round(COBpredBGs[COBpredBGs.length-1]);
        eventualBG = Math.max(eventualBG, round(COBpredBGs[COBpredBGs.length-1]));
        console.error("COBpredBG: " + round(COBpredBGs[COBpredBGs.length-1]) );
    }
    if (ci > 0 || remainingCIpeak > 0) {
        if (enableUAM) {
            UAMpredBGs.forEach(function(p, i, theArray) {
                theArray[i] = round(Math.min(401,Math.max(39,p)));
            });
            for (i=UAMpredBGs.length-1; i > 12; i--) {
                if (UAMpredBGs[i-1] !== UAMpredBGs[i]) { break; }
                else { UAMpredBGs.pop(); }
            }
            rT.predBGs.UAM = UAMpredBGs;
            lastUAMpredBG=round(UAMpredBGs[UAMpredBGs.length-1]);
            if (UAMpredBGs[UAMpredBGs.length-1]) {
                eventualBG = Math.max(eventualBG, round(UAMpredBGs[UAMpredBGs.length-1]) );
            }
        }

        // set eventualBG based on COB or UAM predBGs
        rT.eventualBG = eventualBG;
    }

    console.error("UAM Impact:" + uci + "mg/dL per 5m; UAM Duration:" + UAMduration + "hours");

    minIOBPredBG = Math.max(39,minIOBPredBG);
    minCOBPredBG = Math.max(39,minCOBPredBG);
    minUAMPredBG = Math.max(39,minUAMPredBG);
    minPredBG = round(minIOBPredBG);

    var fractionCarbsLeft = meal_data.mealCOB/meal_data.carbs;
    // if we have COB and UAM is enabled, average both
    if ( minUAMPredBG < 999 && minCOBPredBG < 999 ) {
        // weight COBpredBG vs. UAMpredBG based on how many carbs remain as COB
        avgPredBG = round( (1-fractionCarbsLeft)*UAMpredBG + fractionCarbsLeft*COBpredBG );
        // if UAM is disabled, average IOB and COB
    } else if ( minCOBPredBG < 999 ) {
        avgPredBG = round( (IOBpredBG + COBpredBG)/2 );
        // if we have UAM but no COB, average IOB and UAM
    } else if ( minUAMPredBG < 999 ) {
        avgPredBG = round( (IOBpredBG + UAMpredBG)/2 );
    } else {
        avgPredBG = round( IOBpredBG );
    }
    // if avgPredBG is below minZTGuardBG, bring it up to that level
    if ( minZTGuardBG > avgPredBG ) {
        avgPredBG = minZTGuardBG;
    }

    // if we have both minCOBGuardBG and minUAMGuardBG, blend according to fractionCarbsLeft
    if ( (cid || remainingCIpeak > 0) ) {
        if ( enableUAM ) {
            minGuardBG = fractionCarbsLeft*minCOBGuardBG + (1-fractionCarbsLeft)*minUAMGuardBG;
        } else {
            minGuardBG = minCOBGuardBG;
        }
    } else if ( enableUAM ) {
        minGuardBG = minUAMGuardBG;
    } else {
        minGuardBG = minIOBGuardBG;
    }
    minGuardBG = round(minGuardBG);
    //console.error(minCOBGuardBG, minUAMGuardBG, minIOBGuardBG, minGuardBG);

    var minZTUAMPredBG = minUAMPredBG;
    // if minZTGuardBG is below threshold, bring down any super-high minUAMPredBG by averaging
    // this helps prevent UAM from giving too much insulin in case absorption falls off suddenly
    if ( minZTGuardBG < threshold ) {
        minZTUAMPredBG = (minUAMPredBG + minZTGuardBG) / 2;
    // if minZTGuardBG is between threshold and target, blend in the averaging
    } else if ( minZTGuardBG < target_bg ) {
        // target 100, threshold 70, minZTGuardBG 85 gives 50%: (85-70) / (100-70)
        var blendPct = (minZTGuardBG-threshold) / (target_bg-threshold);
        var blendedMinZTGuardBG = minUAMPredBG*blendPct + minZTGuardBG*(1-blendPct);
        minZTUAMPredBG = (minUAMPredBG + blendedMinZTGuardBG) / 2;
        //minZTUAMPredBG = minUAMPredBG - target_bg + minZTGuardBG;
    // if minUAMPredBG is below minZTGuardBG, bring minUAMPredBG up by averaging
    // this allows more insulin if lastUAMPredBG is below target, but minZTGuardBG is still high
    } else if ( minZTGuardBG > minUAMPredBG ) {
        minZTUAMPredBG = (minUAMPredBG + minZTGuardBG) / 2;
    }
    minZTUAMPredBG = round(minZTUAMPredBG);
    //console.error("minUAMPredBG:",minUAMPredBG,"minZTGuardBG:",minZTGuardBG,"minZTUAMPredBG:",minZTUAMPredBG);
    // if any carbs have been entered recently
    if (meal_data.carbs) {

        // if UAM is disabled, use max of minIOBPredBG, minCOBPredBG
        if ( ! enableUAM && minCOBPredBG < 999 ) {
            minPredBG = round(Math.max(minIOBPredBG, minCOBPredBG));
        // if we have COB, use minCOBPredBG, or blendedMinPredBG if it's higher
        } else if ( minCOBPredBG < 999 ) {
            // calculate blendedMinPredBG based on how many carbs remain as COB
            var blendedMinPredBG = fractionCarbsLeft*minCOBPredBG + (1-fractionCarbsLeft)*minZTUAMPredBG;
            // if blendedMinPredBG > minCOBPredBG, use that instead
            minPredBG = round(Math.max(minIOBPredBG, minCOBPredBG, blendedMinPredBG));
        // if carbs have been entered, but have expired, use minUAMPredBG
        } else if ( enableUAM ) {
            minPredBG = minZTUAMPredBG;
        } else {
            minPredBG = minGuardBG;
        }
    // in pure UAM mode, use the higher of minIOBPredBG,minUAMPredBG
    } else if ( enableUAM ) {
        minPredBG = round(Math.max(minIOBPredBG,minZTUAMPredBG));
    }

    // make sure minPredBG isn't higher than avgPredBG
    minPredBG = Math.min( minPredBG, avgPredBG );

// Print summary variables based on predBGs etc.

    process.stderr.write("minPredBG: "+minPredBG+" minIOBPredBG: "+minIOBPredBG+" minZTGuardBG: "+minZTGuardBG);
    if (minCOBPredBG < 999) {
        process.stderr.write(" minCOBPredBG: "+minCOBPredBG);
    }
    if (minUAMPredBG < 999) {
        process.stderr.write(" minUAMPredBG: "+minUAMPredBG);
    }
    console.error(" avgPredBG:" + avgPredBG + " COB/Carbs:" + meal_data.mealCOB + "/" + meal_data.carbs);
    // But if the COB line falls off a cliff, don't trust UAM too much:
    // use maxCOBPredBG if it's been set and lower than minPredBG
    if ( maxCOBPredBG > bg ) {
        minPredBG = Math.min(minPredBG, maxCOBPredBG);
    }

    rT.COB=meal_data.mealCOB;
    rT.IOB=iob_data.iob;
    rT.BGI=convert_bg(bgi,profile);
    rT.deviation=convert_bg(deviation, profile);
    rT.ISF=convert_bg(sens, profile);
    rT.CR=round(carbRatio, 1);
    rT.target_bg=convert_bg(target_bg, profile);
    rT.current_target=round(target_bg, 0);
    rT.reason = isfreason + ", COB: " + rT.COB + ", Dev: " + rT.deviation + ", BGI: " + rT.BGI + ", CR: " + rT.CR + ", Target: " + targetLog + ", minPredBG " + convert_bg(minPredBG, profile) + ", minGuardBG " + convert_bg(minGuardBG, profile) + ", IOBpredBG " + convert_bg(lastIOBpredBG, profile);
    if (lastCOBpredBG > 0) {
        rT.reason += ", COBpredBG " + convert_bg(lastCOBpredBG, profile);
    }
    if (lastUAMpredBG > 0) {
        rT.reason += ", UAMpredBG " + convert_bg(lastUAMpredBG, profile);
    }
    rT.reason += tddReason;

    rT.reason += "; "; // reason.conclusion started
// Use minGuardBG to prevent overdosing in hypo-risk situations
    // use naive_eventualBG if above 40, but switch to minGuardBG if both eventualBGs hit floor of 39
    var carbsReqBG = naive_eventualBG;
    if ( carbsReqBG < 40 ) {
        carbsReqBG = Math.min( minGuardBG, carbsReqBG );
    }
    var bgUndershoot = threshold - carbsReqBG;
    // calculate how long until COB (or IOB) predBGs drop below min_bg
    var minutesAboveMinBG = 240;
    var minutesAboveThreshold = 240;
    if (meal_data.mealCOB > 0 && ( ci > 0 || remainingCIpeak > 0 )) {
        for (i=0; i<COBpredBGs.length; i++) {
            if ( COBpredBGs[i] < min_bg ) {
                minutesAboveMinBG = 5*i;
                break;
            }
        }
        for (i=0; i<COBpredBGs.length; i++) {
            if ( COBpredBGs[i] < threshold ) {
                minutesAboveThreshold = 5*i;
                break;
            }
        }
    }

    else {
        for (i=0; i<IOBpredBGs.length; i++) {
            //console.error(IOBpredBGs[i], min_bg);
            if ( IOBpredBGs[i] < min_bg ) {
                minutesAboveMinBG = 5*i;
                break;
            }
        }
        for (i=0; i<IOBpredBGs.length; i++) {
            //console.error(IOBpredBGs[i], threshold);
            if ( IOBpredBGs[i] < threshold ) {
                minutesAboveThreshold = 5*i;
                break;
            }
        }
    }

    if (enableSMB && minGuardBG < threshold) {
        console.error("minGuardBG " + convert_bg(minGuardBG, profile) + " projected below " + convert_bg(threshold, profile) + " - disabling SMB");
        rT.manualBolusErrorString = 1;
        rT.minGuardBG = minGuardBG;
        rT.insulinForManualBolus = round((rT.eventualBG - rT.target_bg) / sens, 2);

        //rT.reason += "minGuardBG "+minGuardBG+"<"+threshold+": SMB disabled; ";
        enableSMB = false;
    }
// Disable SMB for sudden rises (often caused by calibrations or activation/deactivation of Dexcom's noise-filtering algorithm)
// Added maxDelta_bg_threshold as a hidden preference and included a cap at 0.4 as a safety limitLog
var maxDelta_bg_threshold;
    if (typeof profile.maxDelta_bg_threshold === 'undefined') {
        maxDelta_bg_threshold = 0.2;
    }
    if (typeof profile.maxDelta_bg_threshold !== 'undefined') {
        maxDelta_bg_threshold = Math.min(profile.maxDelta_bg_threshold, 0.4);
    }
    if ( maxDelta > maxDelta_bg_threshold * bg ) {
        console.error("maxDelta " + convert_bg(maxDelta, profile)+ " > " + 100 * maxDelta_bg_threshold + "% of BG " + convert_bg(bg, profile) + " - disabling SMB");
        rT.reason += "maxDelta " + convert_bg(maxDelta, profile) + " > " + 100 * maxDelta_bg_threshold + "% of BG " + convert_bg(bg, profile) + " - SMB disabled!, ";
        enableSMB = false;
    }

// Calculate carbsReq (carbs required to avoid a hypo)
    console.error("BG projected to remain above " + convert_bg(min_bg, profile) + " for " + minutesAboveMinBG + "minutes");
    if ( minutesAboveThreshold < 240 || minutesAboveMinBG < 60 ) {
        console.error("BG projected to remain above " + convert_bg(threshold,profile) + " for " + minutesAboveThreshold + "minutes");
    }
    // include at least minutesAboveThreshold worth of zero temps in calculating carbsReq
    // always include at least 30m worth of zero temp (carbs to 80, low temp up to target)
    var zeroTempDuration = minutesAboveThreshold;
    // BG undershoot, minus effect of zero temps until hitting min_bg, converted to grams, minus COB
    var zeroTempEffect = profile.current_basal*overrideFactor*sens*zeroTempDuration/60;
    // don't count the last 25% of COB against carbsReq
    var COBforCarbsReq = Math.max(0, meal_data.mealCOB - 0.25*meal_data.carbs);
    var carbsReq = (bgUndershoot - zeroTempEffect) / csf - COBforCarbsReq;
    zeroTempEffect = round(zeroTempEffect);
    carbsReq = round(carbsReq);
    console.error("naive_eventualBG:",naive_eventualBG,"bgUndershoot:",bgUndershoot,"zeroTempDuration:",zeroTempDuration,"zeroTempEffect:",zeroTempEffect,"carbsReq:",carbsReq);
    if ( meal_data.reason == "Could not parse clock data" ) {
        console.error("carbsReq unknown: Could not parse clock data");
    } else if ( carbsReq >= profile.carbsReqThreshold && minutesAboveThreshold <= 45 ) {
        rT.carbsReq = carbsReq;
        rT.reason += carbsReq + " add'l carbs req w/in " + minutesAboveThreshold + "m; ";
    }

// Begin core dosing logic: check for situations requiring low or high temps, and return appropriate temp after first match

    // don't low glucose suspend if IOB is already super negative and BG is rising faster than predicted
    var worstCaseInsulinReq = 0;
    var durationReq = 0;
    if (bg < threshold && iob_data.iob < -profile.current_basal*overrideFactor*20/60 && minDelta > 0 && minDelta > expectedDelta) {
        rT.reason += "IOB "+iob_data.iob+" < " + round(-profile.current_basal*overrideFactor*20/60,2);
        rT.reason += " and minDelta " + convert_bg(minDelta, profile) + " > " + "expectedDelta " + convert_bg(expectedDelta, profile) + "; ";
     // predictive low glucose suspend mode: BG is / is projected to be < threshold
    } else if ( bg < threshold || minGuardBG < threshold ) {
        rT.reason += "minGuardBG " + convert_bg(minGuardBG, profile) + "<" + convert_bg(threshold, profile);
        bgUndershoot = target_bg - minGuardBG;

        if (minGuardBG < threshold) {
            rT.manualBolusErrorString = 2;
            rT.minGuardBG = minGuardBG;
        }
        rT.insulinForManualBolus =  round((eventualBG - target_bg) / sens, 2);

        worstCaseInsulinReq = bgUndershoot / sens;
        durationReq = round(60*worstCaseInsulinReq / profile.current_basal*overrideFactor);
        durationReq = round(durationReq/30)*30;
        // always set a 30-120m zero temp (oref0-pump-loop will let any longer SMB zero temp run)
        durationReq = Math.min(120,Math.max(30,durationReq));
        return tempBasalFunctions.setTempBasal(0, durationReq, profile, rT, currenttemp);
    }

    // if not in LGS mode, cancel temps before the top of the hour to reduce beeping/vibration
    // console.error(profile.skip_neutral_temps, rT.deliverAt.getMinutes());
    if ( profile.skip_neutral_temps && rT.deliverAt.getMinutes() >= 55 ) {
        if (!enableSMB) {
            rT.reason += "; Canceling temp at " + (60 - rT.deliverAt.getMinutes()) + "min before turn of the hour to avoid beeping of MDT. SMB are disabled anyways.";
            return tempBasalFunctions.setTempBasal(0, 0, profile, rT, currenttemp);
        } else {
             console.error((60 - rT.deliverAt.getMinutes()) + "min before turn of the hour, but SMB's are enabled - not skipping neutral temps.")
        }
    }

    var insulinReq = 0;
    var rate = basal;
    var insulinScheduled = 0;
    if (eventualBG < min_bg) { // if eventual BG is below target:
        rT.reason += "Eventual BG " + convert_bg(eventualBG, profile) + " < " + convert_bg(min_bg, profile);
        // if 5m or 30m avg BG is rising faster than expected delta
        if ( minDelta > expectedDelta && minDelta > 0 && !carbsReq ) {
            // if naive_eventualBG < 40, set a 30m zero temp (oref0-pump-loop will let any longer SMB zero temp run)
            if (naive_eventualBG < 40) {
                rT.reason += ", naive_eventualBG < 40. ";
                return tempBasalFunctions.setTempBasal(0, 30, profile, rT, currenttemp);
            }
            if (glucose_status.delta > minDelta) {
                rT.reason += ", but Delta " + convert_bg(tick, profile) + " > expectedDelta " + convert_bg(expectedDelta, profile);
            } else {
                rT.reason += ", but Min. Delta " + minDelta.toFixed(2) + " > Exp. Delta " + convert_bg(expectedDelta, profile);
            }
            if (currenttemp.duration > 15 && (round_basal(basal, profile) === round_basal(currenttemp.rate, profile))) {
                rT.reason += ", temp " + currenttemp.rate + " ~ req " + basal + "U/hr. ";
                return rT;
            } else {
                rT.reason += "; setting current basal of " + basal + " as temp. ";
                return tempBasalFunctions.setTempBasal(basal, 30, profile, rT, currenttemp);
            }
        }

        // calculate 30m low-temp required to get projected BG up to target
        // multiply by 2 to low-temp faster for increased hypo safety
        insulinReq = 2 * Math.min(0, (eventualBG - target_bg) / sens);
        insulinReq = round( insulinReq , 2);
        // calculate naiveInsulinReq based on naive_eventualBG
        var naiveInsulinReq = Math.min(0, (naive_eventualBG - target_bg) / sens);
        naiveInsulinReq = round( naiveInsulinReq , 2);
        if (minDelta < 0 && minDelta > expectedDelta) {
            // if we're barely falling, newinsulinReq should be barely negative
            var newinsulinReq = round(( insulinReq * (minDelta / expectedDelta) ), 2);
            //console.error("Increasing insulinReq from " + insulinReq + " to " + newinsulinReq);
            insulinReq = newinsulinReq;
        }
        // rate required to deliver insulinReq less insulin over 30m:
        rate = basal + (2 * insulinReq);
        rate = round_basal(rate, profile);

        // if required temp < existing temp basal
        insulinScheduled = currenttemp.duration * (currenttemp.rate - basal) / 60;
        // if current temp would deliver a lot (30% of basal) less than the required insulin,
        // by both normal and naive calculations, then raise the rate
        var minInsulinReq = Math.min(insulinReq,naiveInsulinReq);

        console.log("naiveInsulinReq:" + naiveInsulinReq);

        if (insulinScheduled < minInsulinReq - basal*0.3) {
            rT.reason += ", " + currenttemp.duration + "m@" + (currenttemp.rate).toFixed(2) + " is a lot less than needed. ";
            return tempBasalFunctions.setTempBasal(rate, 30, profile, rT, currenttemp);
        }
        if (typeof currenttemp.rate !== 'undefined' && (currenttemp.duration > 5 && rate >= currenttemp.rate * 0.8)) {
            rT.reason += ", temp " + currenttemp.rate + " ~< req " + rate + "U/hr. ";
            return rT;
        }

        else {
            // calculate a long enough zero temp to eventually correct back up to target
            if ( rate <=0 ) {
                bgUndershoot = target_bg - naive_eventualBG;
                worstCaseInsulinReq = bgUndershoot / sens;
                durationReq = round(60*worstCaseInsulinReq / profile.current_basal * overrideFactor);
                if (durationReq < 0) {
                    durationReq = 0;
                // don't set a temp longer than 120 minutes
                } else {
                    durationReq = round(durationReq/30)*30;
                    durationReq = Math.min(120,Math.max(0,durationReq));
                }
                //console.error(durationReq);
                if (durationReq > 0) {
                    rT.reason += ", setting " + durationReq + "m zero temp. ";
                    return tempBasalFunctions.setTempBasal(rate, durationReq, profile, rT, currenttemp);
                }
            }

            else {
                rT.reason += ", setting " + rate + "U/hr. ";
            }
            return tempBasalFunctions.setTempBasal(rate, 30, profile, rT, currenttemp);
        }
    }

    // if eventual BG is above min_bg but BG is falling faster than expected Delta
    if (minDelta < expectedDelta) {

        rT.minDelta = minDelta;
        rT.expectedDelta = expectedDelta;

        //Describe how the glucose is changing
        if (expectedDelta - minDelta >= 2 || (expectedDelta + (-1 * minDelta) >= 2)) {
            if (minDelta >= 0 && expectedDelta > 0) {
                rT.manualBolusErrorString = 3;
            }
            else if ((minDelta < 0 && expectedDelta <= 0) ||  (minDelta < 0 && expectedDelta >= 0)) {
                rT.manualBolusErrorString = 4;
            }
            else {
                rT.manualBolusErrorString = 5;
            }
        }

        rT.insulinForManualBolus = round((rT.eventualBG - rT.target_bg) / sens, 2);

        // if in SMB mode, don't cancel SMB zero temp
        if (! (microBolusAllowed && enableSMB)) {
            if (glucose_status.delta < minDelta) {
                rT.reason += "Eventual BG " + convert_bg(eventualBG, profile) + " > " + convert_bg(min_bg, profile) + " but Delta " + convert_bg(tick, profile) + " < Exp. Delta " + convert_bg(expectedDelta, profile);
            } else {
                rT.reason += "Eventual BG " + convert_bg(eventualBG, profile) + " > " + convert_bg(min_bg, profile) + " but Min. Delta " + minDelta.toFixed(2) + " < Exp. Delta " + convert_bg(expectedDelta, profile);
            }
            if (currenttemp.duration > 15 && (round_basal(basal, profile) === round_basal(currenttemp.rate, profile))) {
                rT.reason += ", temp " + currenttemp.rate + " ~ req " + basal + "U/hr. ";
                return rT;
            } else {
                rT.reason += "; setting current basal of " + basal + " as temp. ";
                return tempBasalFunctions.setTempBasal(basal, 30, profile, rT, currenttemp);
            }
        }
    }
    // eventualBG or minPredBG is below max_bg
    if (Math.min(eventualBG,minPredBG) < max_bg) {
        if (minPredBG < min_bg && eventualBG > min_bg) {
            rT.manualBolusErrorString = 6;
            rT.insulinForManualBolus = round((rT.eventualBG - rT.target_bg) / sens, 2);
        }

        // Moving this out of the if condition in L1429, so that minPredBG is becomes always available in rT object (aka Trio's determination)
        rT.minPredBG = minPredBG;

        // if in SMB mode, don't cancel SMB zero temp
        if (! (microBolusAllowed && enableSMB )) {
            rT.reason += convert_bg(eventualBG, profile)+ "-" + convert_bg(minPredBG, profile) + " in range: no temp required";
            if (currenttemp.duration > 15 && (round_basal(basal, profile) === round_basal(currenttemp.rate, profile))) {
                rT.reason += ", temp " + currenttemp.rate + " ~ req " + basal + "U/hr. ";
                return rT;
            } else {
                rT.reason += "; setting current basal of " + basal + " as temp. ";
                return tempBasalFunctions.setTempBasal(basal, 30, profile, rT, currenttemp);
            }
        }
    }

    // eventual BG is at/above target
    // if iob is over max, just cancel any temps
    if ( eventualBG >= max_bg ) {
        rT.reason += "Eventual BG " + convert_bg(eventualBG, profile) + " >= " +  convert_bg(max_bg, profile) + ", ";
        if (eventualBG > max_bg) {
        rT.insulinForManualBolus = round((eventualBG - target_bg) / sens, 2);
        }
    }
    if (iob_data.iob > max_iob) {
        rT.reason += "IOB " + round(iob_data.iob,2) + " > max_iob " + max_iob;
        if (currenttemp.duration > 15 && (round_basal(basal, profile) === round_basal(currenttemp.rate, profile))) {
            rT.reason += ", temp " + currenttemp.rate + " ~ req " + basal + "U/hr. ";
            return rT;
        } else {
            rT.reason += "; setting current basal of " + basal + " as temp. ";
            return tempBasalFunctions.setTempBasal(basal, 30, profile, rT, currenttemp);
        }
    }

    else { // otherwise, calculate 30m high-temp required to get projected BG down to target
        // insulinReq is the additional insulin required to get minPredBG down to target_bg
        //console.error(minPredBG,eventualBG);
        insulinReq = round( (Math.min(minPredBG,eventualBG) - target_bg) / sens, 2);
        insulinForManualBolus = round((eventualBG - target_bg) / sens, 2);
        // if that would put us over max_iob, then reduce accordingly
        if (insulinReq > max_iob-iob_data.iob) {
            console.error("SMB limited by maxIOB: " + max_iob-iob_data.iob + " (. insulinReq: " + insulinReq + " U)");
            rT.reason += "max_iob " + max_iob + ", ";
            insulinReq = max_iob-iob_data.iob;
        } else { console.error("SMB not limited by maxIOB ( insulinReq: " + insulinReq + " U).");}

        if (insulinForManualBolus > max_iob-iob_data.iob) {
            console.error("Ev. Bolus limited by maxIOB: " + max_iob-iob_data.iob + " (. insulinForManualBolus: " + insulinForManualBolus + " U)");
            rT.reason += "max_iob " + max_iob + ", ";
        } else { console.error("Ev. Bolus would not be limited by maxIOB ( insulinForManualBolus: " + insulinForManualBolus + " U).");}

        // rate required to deliver insulinReq more insulin over 30m:
        rate = basal + (2 * insulinReq);
        rate = round_basal(rate, profile);
        insulinReq = round(insulinReq,3);
        rT.insulinReq = insulinReq;
        //console.error(iob_data.lastBolusTime);
        // minutes since last bolus
        var lastBolusAge = round(( new Date(systemTime).getTime() - iob_data.lastBolusTime ) / 60000,1);

        //console.error(lastBolusAge);
        //console.error(profile.temptargetSet, target_bg, rT.COB);
        // only allow microboluses with COB or low temp targets, or within DIA hours of a bolus
        if (microBolusAllowed && enableSMB && bg > threshold) {
            // never bolus more than maxSMBBasalMinutes worth of basal


            var smbMinutesSetting =  30;
            if (typeof profile.maxSMBBasalMinutes !== 'undefined') {
                smbMinutesSetting = profile.maxSMBBasalMinutes;
            }
            var uamMinutesSetting = 30;
            if (typeof profile.maxUAMSMBBasalMinutes !== 'undefined') {
                uamMinutesSetting = profile.maxUAMSMBBasalMinutes;
            }

            if (oref2_variables.useOverride && advancedSettings && smbMinutes !== smbMinutesSetting) {
                console.error("SMB Max Minutes - setting overriden from " + smbMinutesSetting + " to " + smbMinutes);
                smbMinutesSetting = smbMinutes;
            }
            if (oref2_variables.useOverride && advancedSettings && uamMinutes !== uamMinutesSetting) {
                console.error("UAM Max Minutes - setting overriden from " + uamMinutesSetting + " to " + uamMinutes);
                uamMinutesSetting = uamMinutes;
            }

            var mealInsulinReq = round( meal_data.mealCOB / carbRatio ,3);
            var maxBolus = 0;
            if (typeof smbMinutesSetting === 'undefined' ) {
                maxBolus = round(profile.current_basal *overrideFactor * 30 / 60 ,1);
                console.error("smbMinutesSetting undefined: defaulting to 30m");

                if( insulinReq > maxBolus ) {
                  console.error("SMB limited by maxBolus: " + maxBolus + " ( " + insulinReq + " U)");
                }
            } else if ( iob_data.iob > mealInsulinReq && iob_data.iob > 0 ) {
                console.error("IOB" + iob_data.iob + "> COB" + meal_data.mealCOB + "; mealInsulinReq =" + mealInsulinReq);
                if (uamMinutesSetting) {
                    console.error("maxUAMSMBBasalMinutes: " + uamMinutesSetting + ", profile.current_basal: " + profile.current_basal * overrideFactor);
                    maxBolus = round(profile.current_basal * overrideFactor * uamMinutesSetting / 60 ,1);
                } else {
                    console.error("maxUAMSMBBasalMinutes undefined: defaulting to 30m");
                    maxBolus = round( profile.current_basal  * overrideFactor * 30 / 60 ,1);
                }
                if( insulinReq > maxBolus ) {
                  console.error("SMB limited by maxUAMSMBBasalMinutes [ " + uamMinutesSetting + "m ]: " + maxBolus + "U ( " + insulinReq + "U )");
                } else { console.error("SMB is not limited by maxUAMSMBBasalMinutes. ( insulinReq: " + insulinReq + "U )"); }
            } else {
                console.error(".maxSMBBasalMinutes: " + smbMinutesSetting + ", profile.current_basal: " + profile.current_basal * overrideFactor);
                maxBolus = round(profile.current_basal  * overrideFactor * smbMinutesSetting / 60 ,1);
                if( insulinReq > maxBolus ) {
                  console.error("SMB limited by maxSMBBasalMinutes: " + smbMinutesSetting + "m ]: " + maxBolus + "U ( insulinReq: " + insulinReq + "U )");
                } else { console.error("SMB is not limited by maxSMBBasalMinutes. ( insulinReq: " + insulinReq + "U )"); }
            }
            // bolus 1/2 the insulinReq, up to maxBolus, rounding down to nearest bolus increment
            var bolusIncrement = profile.bolus_increment;
            //if (profile.bolus_increment) { bolusIncrement=profile.bolus_increment };
            var roundSMBTo = 1 / bolusIncrement;

            var smb_ratio = Math.min(profile.smb_delivery_ratio, 1);

            if (smb_ratio != 0.5) {
                console.error("SMB Delivery Ratio changed from default 0.5 to " + round(smb_ratio,2))
            }
            var microBolus = Math.min(insulinReq*smb_ratio, maxBolus);

            microBolus = Math.floor(microBolus*roundSMBTo)/roundSMBTo;
            // calculate a long enough zero temp to eventually correct back up to target
            var smbTarget = target_bg;
            worstCaseInsulinReq = (smbTarget - (naive_eventualBG + minIOBPredBG)/2 ) / sens;
            durationReq = round(60*worstCaseInsulinReq / profile.current_basal * overrideFactor);

            // if insulinReq > 0 but not enough for a microBolus, don't set an SMB zero temp
            if (insulinReq > 0 && microBolus < bolusIncrement) {
                durationReq = 0;
            }

            var smbLowTempReq = 0;
            if (durationReq <= 0) {
                durationReq = 0;
            // don't set an SMB zero temp longer than 60 minutes
            } else if (durationReq >= 30) {
                durationReq = round(durationReq/30)*30;
                durationReq = Math.min(60,Math.max(0,durationReq));
            } else {
                // if SMB durationReq is less than 30m, set a nonzero low temp
                smbLowTempReq = round( basal * durationReq/30 ,2);
                durationReq = 30;
            }
            rT.reason += " insulinReq " + insulinReq;
            if (microBolus >= maxBolus) {
                rT.reason +=  "; maxBolus " + maxBolus;
            }
            if (durationReq > 0) {
                rT.reason += "; setting " + durationReq + "m low temp of " + smbLowTempReq + "U/h";
            }
            rT.reason += ". ";

            //allow SMBs every 3 minutes by default
            var SMBInterval = 3;
            if (profile.SMBInterval) {
                // allow SMBIntervals between 1 and 10 minutes
                SMBInterval = Math.min(10,Math.max(1,profile.SMBInterval));
            }
            var nextBolusMins = round(SMBInterval-lastBolusAge,0);
            var nextBolusSeconds = round((SMBInterval - lastBolusAge) * 60, 0) % 60;
            //console.error(naive_eventualBG, insulinReq, worstCaseInsulinReq, durationReq);
            console.error("naive_eventualBG " + naive_eventualBG + "," + durationReq + "m " + smbLowTempReq + "U/h temp needed; last bolus " + lastBolusAge +"m ago; maxBolus: " + maxBolus);

            if (lastBolusAge > SMBInterval) {
                if (microBolus > 0) {
                    rT.units = microBolus;
                    rT.reason += "Microbolusing " + microBolus + "U. ";
                }
            } else {
                rT.reason += "Waiting " + nextBolusMins + "m " + nextBolusSeconds + "s to microbolus again. ";
            }
            //rT.reason += ". ";

            // if no zero temp is required, don't return yet; allow later code to set a high temp
            if (durationReq > 0) {
                rT.rate = smbLowTempReq;
                rT.duration = durationReq;
                return rT;
            }

        }

        var maxSafeBasal = tempBasalFunctions.getMaxSafeBasal(profile);


        if (bg == 400) {
            return tempBasalFunctions.setTempBasal(profile.current_basal, 30, profile, rT, currenttemp);
        }

        if (rate > maxSafeBasal) {
            rT.reason += "adj. req. rate: " + rate + " to maxSafeBasal: " + round(maxSafeBasal,2) + ", ";
            rate = round_basal(maxSafeBasal, profile);
        }

        insulinScheduled = currenttemp.duration * (currenttemp.rate - basal) / 60;
        if (insulinScheduled >= insulinReq * 2) { // if current temp would deliver >2x more than the required insulin, lower the rate
            rT.reason += currenttemp.duration + "m@" + (currenttemp.rate).toFixed(2) + " > 2 * insulinReq. Setting temp basal of " + rate + "U/hr. ";
            return tempBasalFunctions.setTempBasal(rate, 30, profile, rT, currenttemp);
        }

        if (typeof currenttemp.duration === 'undefined' || currenttemp.duration === 0) { // no temp is set
            rT.reason += "no temp, setting " + rate + "U/hr. ";
            return tempBasalFunctions.setTempBasal(rate, 30, profile, rT, currenttemp);
        }

        if (currenttemp.duration > 5 && (round_basal(rate, profile) <= round_basal(currenttemp.rate, profile))) { // if required temp <~ existing temp basal
            rT.reason += "temp " + currenttemp.rate + " >~ req " + rate + "U/hr. ";
            return rT;
        }

        // required temp > existing temp basal
        rT.reason += "temp " + currenttemp.rate + "<" + rate + "U/hr. ";
        return tempBasalFunctions.setTempBasal(rate, 30, profile, rT, currenttemp);
    }

};

module.exports = determine_basal;
