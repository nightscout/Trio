import Foundation

struct Profile: Codable {
    // Kotlin-defined properties from AndroidAPS OapsProfile.kt
    // with defaults pulled from profile.js
    var dia: Decimal?
    var min5mCarbImpact: Decimal = 8
    var maxIob: Decimal = 0 // if max_iob is not provided, will default to zero
    var maxDailyBasal: Decimal?
    var maxBasal: Decimal?
    var minBg: Decimal?
    var maxBg: Decimal?
    @JavascriptOptional var targetBg: Decimal?
    var smbDeliveryRatio: Decimal = 0.5
    var carbRatio: Decimal?
    var sens: Decimal?
    var maxDailySafetyMultiplier: Decimal = 3
    var currentBasalSafetyMultiplier: Decimal = 4
    var highTemptargetRaisesSensitivity: Bool = false // raise sensitivity for temptargets >= 101
    var lowTemptargetLowersSensitivity: Bool = false // lower sensitivity for temptargets <= 99
    var sensitivityRaisesTarget: Bool = false // raise BG target when autosens detects sensitivity
    var resistanceLowersTarget: Bool = false // lower BG target when autosens detects resistance
    var halfBasalExerciseTarget: Decimal = 160 // when temptarget is 160 mg/dL *and* exercise_mode=true, run 50% basal
    var maxCOB: Decimal = 120 // maximum carbs a typical body can absorb over 4 hours
    var skipNeutralTemps: Bool = false
    var remainingCarbsCap: Decimal = 90
    var enableUAM: Bool = false
    var a52RiskEnable: Bool = false
    var smbInterval: Decimal = 3
    var enableSMBWithCOB: Bool = false
    var enableSMBWithTemptarget: Bool = false
    var allowSMBWithHighTemptarget: Bool = false
    var enableSMBAlways: Bool = false
    var enableSMBAfterCarbs: Bool = false
    var maxSMBBasalMinutes: Decimal = 30
    var maxUAMSMBBasalMinutes: Decimal = 30
    var bolusIncrement: Decimal = 0.1
    var carbsReqThreshold: Decimal = 1
    var currentBasal: Decimal?
    var temptargetSet: Bool?
    var autosensMax: Decimal = 1.2
    var autosensMin: Decimal = 0.7
    var outUnits: GlucoseUnits?

    // Additional properties
    var maxMealAbsorptionTime: Decimal = 6.0
    var rewindResetsAutosens: Bool = true
    var remainingCarbsFraction: Decimal = 1.0
    var unsuspendIfNoTemp: Bool = false
    var autotuneIsfAdjustmentFraction: Decimal = 1.0
    var enableSMBHighBg: Bool = false
    var enableSMBHighBgTarget: Decimal = 110
    var maxDeltaBgThreshold: Decimal = 0.2
    var curve: InsulinCurve = .rapidActing
    var useCustomPeakTime: Bool = false
    var insulinPeakTime: Decimal = 75
    var noisyCGMTargetMultiplier: Decimal = 1.3
    var suspendZerosIob: Bool = true
    var calcGlucoseNoise: Bool = false
    var adjustmentFactor: Decimal = 0.8
    var adjustmentFactorSigmoid: Decimal = 0.5
    var useNewFormula: Bool = false
    var sigmoid: Bool = false
    var weightPercentage: Decimal = 0.65
    var tddAdjBasal: Bool = false
    var thresholdSetting: Decimal = 60
    var model: String?
    var basalprofile: [BasalProfileEntry]?
    var isfProfile: ComputedInsulinSensitivities?
    var bgTargets: ComputedBGTargets?
    var carbRatios: CarbRatios?

    private enum CodingKeys: String, CodingKey {
        case dia
        case min5mCarbImpact = "min_5m_carbimpact"
        case maxIob = "max_iob"
        case maxDailyBasal = "max_daily_basal"
        case maxBasal = "max_basal"
        case minBg = "min_bg"
        case maxBg = "max_bg"
        case targetBg = "target_bg"
        case smbDeliveryRatio = "smb_delivery_ratio"
        case carbRatio = "carb_ratio"
        case sens
        case maxDailySafetyMultiplier = "max_daily_safety_multiplier"
        case currentBasalSafetyMultiplier = "current_basal_safety_multiplier"
        case highTemptargetRaisesSensitivity = "high_temptarget_raises_sensitivity"
        case lowTemptargetLowersSensitivity = "low_temptarget_lowers_sensitivity"
        case sensitivityRaisesTarget = "sensitivity_raises_target"
        case resistanceLowersTarget = "resistance_lowers_target"
        case halfBasalExerciseTarget = "half_basal_exercise_target"
        case maxCOB
        case skipNeutralTemps = "skip_neutral_temps"
        case remainingCarbsCap
        case enableUAM
        case a52RiskEnable = "A52_risk_enable"
        case smbInterval = "SMBInterval"
        case enableSMBWithCOB = "enableSMB_with_COB"
        case enableSMBWithTemptarget = "enableSMB_with_temptarget"
        case allowSMBWithHighTemptarget = "allowSMB_with_high_temptarget"
        case enableSMBAlways = "enableSMB_always"
        case enableSMBAfterCarbs = "enableSMB_after_carbs"
        case maxSMBBasalMinutes
        case maxUAMSMBBasalMinutes
        case bolusIncrement = "bolus_increment"
        case carbsReqThreshold
        case currentBasal = "current_basal"
        case temptargetSet
        case autosensMax = "autosens_max"
        case autosensMin = "autosens_min"
        case outUnits = "out_units"
        case maxMealAbsorptionTime
        case rewindResetsAutosens = "rewind_resets_autosens"
        case remainingCarbsFraction
        case unsuspendIfNoTemp = "unsuspend_if_no_temp"
        case autotuneIsfAdjustmentFraction = "autotune_isf_adjustmentFraction"
        case enableSMBHighBg = "enableSMB_high_bg"
        case enableSMBHighBgTarget = "enableSMB_high_bg_target"
        case maxDeltaBgThreshold = "maxDelta_bg_threshold"
        case curve
        case useCustomPeakTime
        case insulinPeakTime
        case noisyCGMTargetMultiplier
        case suspendZerosIob = "suspend_zeros_iob"
        case adjustmentFactor
        case adjustmentFactorSigmoid
        case useNewFormula
        case sigmoid
        case weightPercentage
        case tddAdjBasal
        case thresholdSetting = "threshold_setting"
        case model
        case basalprofile
        case isfProfile
        case bgTargets = "bg_targets"
        case carbRatios = "carb_ratios"
    }
}
