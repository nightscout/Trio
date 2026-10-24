import Foundation

public struct Profile: JSON {
    // Kotlin-defined properties from AndroidAPS OapsProfile.kt
    // with defaults pulled from profile.js
    public var dia: Decimal?
    public var min5mCarbImpact: Decimal = 8
    public var maxIob: Decimal = 0 // if max_iob is not provided, will default to zero
    public var maxDailyBasal: Decimal?
    public var maxBasal: Decimal?
    public var minBg: Decimal?
    public var maxBg: Decimal?
    @JavascriptOptional public var targetBg: Decimal?
    public var smbDeliveryRatio: Decimal = 0.5
    public var carbRatio: Decimal?
    public var sens: Decimal?
    public var maxDailySafetyMultiplier: Decimal = 3
    public var currentBasalSafetyMultiplier: Decimal = 4
    public var highTemptargetRaisesSensitivity: Bool = false // raise sensitivity for temptargets >= 101
    public var lowTemptargetLowersSensitivity: Bool = false // lower sensitivity for temptargets <= 99
    public var sensitivityRaisesTarget: Bool = false // raise BG target when autosens detects sensitivity
    public var resistanceLowersTarget: Bool = false // lower BG target when autosens detects resistance
    public var halfBasalExerciseTarget: Decimal = 160 // when temptarget is 160 mg/dL *and* exercise_mode=true, run 50% basal
    public var maxCOB: Decimal = 120 // maximum carbs a typical body can absorb over 4 hours
    public var skipNeutralTemps: Bool = false
    public var remainingCarbsCap: Decimal = 90
    public var enableUAM: Bool = false
    public var a52RiskEnable: Bool = false
    public var smbInterval: Decimal = 3
    /// Basal Testing: suspend on a genuine low only. Kept out of `CodingKeys` so profile.json,
    /// which the parity goldens compare, is unchanged.
    public var suspendOnly: Bool = false
    public var enableSMBWithCOB: Bool = false
    public var enableSMBWithTemptarget: Bool = false
    public var allowSMBWithHighTemptarget: Bool = false
    public var enableSMBAlways: Bool = false
    public var enableSMBAfterCarbs: Bool = false
    public var maxSMBBasalMinutes: Decimal = 30
    public var maxUAMSMBBasalMinutes: Decimal = 30
    public var bolusIncrement: Decimal = 0.1
    public var carbsReqThreshold: Decimal = 1
    public var currentBasal: Decimal?
    public var temptargetSet: Bool?
    public var autosensMax: Decimal = 1.2
    public var autosensMin: Decimal = 0.7
    public var outUnits: GlucoseUnits?

    // Additional properties
    public var maxMealAbsorptionTime: Decimal = 6.0
    public var rewindResetsAutosens: Bool = true
    public var remainingCarbsFraction: Decimal = 1.0
    public var unsuspendIfNoTemp: Bool = false
    public var autotuneIsfAdjustmentFraction: Decimal = 1.0
    public var enableSMBHighBg: Bool = false
    public var enableSMBHighBgTarget: Decimal = 110
    public var maxDeltaBgThreshold: Decimal = 0.2
    public var curve: InsulinCurve = .rapidActing
    public var useCustomPeakTime: Bool = false
    public var insulinPeakTime: Decimal = 75
    public var noisyCGMTargetMultiplier: Decimal = 1.3
    public var suspendZerosIob: Bool = true
    public var calcGlucoseNoise: Bool = false
    public var adjustmentFactor: Decimal = 0.8
    public var adjustmentFactorSigmoid: Decimal = 0.5
    public var useNewFormula: Bool = false
    public var sigmoid: Bool = false
    public var weightPercentage: Decimal = 0.65
    public var tddAdjBasal: Bool = false
    public var thresholdSetting: Decimal = 60
    public var basalprofile: [BasalProfileEntry]?
    public var isfProfile: ComputedInsulinSensitivities?
    public var bgTargets: ComputedBGTargets?
    public var carbRatios: CarbRatios?
    // rates the paired pump can deliver; injected per determination, never persisted; empty means no paired pump
    public var supportedBasalRates: [Decimal] = []

    public init() {}

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
        case basalprofile
        case isfProfile
        case bgTargets = "bg_targets"
        case carbRatios = "carb_ratios"
    }
}
