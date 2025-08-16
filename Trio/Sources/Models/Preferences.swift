import Foundation

struct Preferences: JSON, Equatable {
    var maxIOB: Decimal = 0
    var maxDailySafetyMultiplier: Decimal = 3
    var currentBasalSafetyMultiplier: Decimal = 4
    var autosensMax: Decimal = 1.2
    var autosensMin: Decimal = 0.7
    var smbDeliveryRatio: Decimal = 0.5
    var rewindResetsAutosens: Bool = true
    var highTemptargetRaisesSensitivity: Bool = false
    var lowTemptargetLowersSensitivity: Bool = false
    var sensitivityRaisesTarget: Bool = false
    var resistanceLowersTarget: Bool = false
    var advTargetAdjustments: Bool = false
    var exerciseMode: Bool = false
    var halfBasalExerciseTarget: Decimal = 160
    var maxCOB: Decimal = 120
    var maxMealAbsorptionTime: Decimal = 6
    var wideBGTargetRange: Bool = false
    var skipNeutralTemps: Bool = false
    var unsuspendIfNoTemp: Bool = false
    var min5mCarbimpact: Decimal = 8
    var remainingCarbsFraction: Decimal = 1.0
    var remainingCarbsCap: Decimal = 90
    var enableUAM: Bool = false
    var a52RiskEnable: Bool = false
    var enableSMBWithCOB: Bool = false
    var enableSMBWithTemptarget: Bool = false
    var enableSMBAlways: Bool = false
    var enableSMBAfterCarbs: Bool = false
    var allowSMBWithHighTemptarget: Bool = false
    var maxSMBBasalMinutes: Decimal = 30
    var maxUAMSMBBasalMinutes: Decimal = 30
    var smbInterval: Decimal = 3
    var bolusIncrement: Decimal = 0.1
    var curve: InsulinCurve = .rapidActing
    var useCustomPeakTime: Bool = false
    var insulinPeakTime: Decimal = 75
    var carbsReqThreshold: Decimal = 1.0
    var noisyCGMTargetMultiplier: Decimal = 1.3
    var suspendZerosIOB: Bool = true
    var timestamp: Date?
    var maxDeltaBGthreshold: Decimal = 0.2
    var adjustmentFactor: Decimal = 0.8
    var adjustmentFactorSigmoid: Decimal = 0.5
    var sigmoid: Bool = false
    var useNewFormula: Bool = false
    var useWeightedAverage: Bool = false
    var weightPercentage: Decimal = 0.35
    var tddAdjBasal: Bool = false
    var enableSMB_high_bg: Bool = false
    var enableSMB_high_bg_target: Decimal = 110
    var threshold_setting: Decimal = 60
    var updateInterval: Decimal = 20
}

extension Preferences {
    private enum CodingKeys: String, CodingKey {
        case maxIOB = "max_iob"
        case maxDailySafetyMultiplier = "max_daily_safety_multiplier"
        case currentBasalSafetyMultiplier = "current_basal_safety_multiplier"
        case autosensMax = "autosens_max"
        case autosensMin = "autosens_min"
        case smbDeliveryRatio = "smb_delivery_ratio"
        case rewindResetsAutosens = "rewind_resets_autosens"
        case highTemptargetRaisesSensitivity = "high_temptarget_raises_sensitivity"
        case lowTemptargetLowersSensitivity = "low_temptarget_lowers_sensitivity"
        case sensitivityRaisesTarget = "sensitivity_raises_target"
        case resistanceLowersTarget = "resistance_lowers_target"
        case advTargetAdjustments = "adv_target_adjustments"
        case exerciseMode = "exercise_mode"
        case halfBasalExerciseTarget = "half_basal_exercise_target"
        case maxCOB
        case maxMealAbsorptionTime
        case wideBGTargetRange = "wide_bg_target_range"
        case skipNeutralTemps = "skip_neutral_temps"
        case unsuspendIfNoTemp = "unsuspend_if_no_temp"
        case min5mCarbimpact = "min_5m_carbimpact"
        case remainingCarbsFraction
        case remainingCarbsCap
        case enableUAM
        case a52RiskEnable = "A52_risk_enable"
        case enableSMBWithCOB = "enableSMB_with_COB"
        case enableSMBWithTemptarget = "enableSMB_with_temptarget"
        case enableSMBAlways = "enableSMB_always"
        case enableSMBAfterCarbs = "enableSMB_after_carbs"
        case allowSMBWithHighTemptarget = "allowSMB_with_high_temptarget"
        case maxSMBBasalMinutes
        case maxUAMSMBBasalMinutes
        case smbInterval = "SMBInterval"
        case bolusIncrement = "bolus_increment"
        case curve
        case useCustomPeakTime
        case insulinPeakTime
        case carbsReqThreshold
        case noisyCGMTargetMultiplier
        case suspendZerosIOB = "suspend_zeros_iob"
        case maxDeltaBGthreshold = "maxDelta_bg_threshold"
        case adjustmentFactor
        case adjustmentFactorSigmoid
        case sigmoid
        case useNewFormula
        case useWeightedAverage
        case weightPercentage
        case tddAdjBasal
        case enableSMB_high_bg
        case enableSMB_high_bg_target
        case threshold_setting
        case updateInterval
    }
}

enum InsulinCurve: String, JSON, Identifiable, CaseIterable {
    case rapidActing = "rapid-acting"
    case ultraRapid = "ultra-rapid"
    case bilinear

    var id: InsulinCurve { self }
}

extension Preferences: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var preferences = Preferences()

        if let maxIOB = try? container.decode(Decimal.self, forKey: .maxIOB) {
            preferences.maxIOB = maxIOB
        }

        if let maxDailySafetyMultiplier = try? container.decode(Decimal.self, forKey: .maxDailySafetyMultiplier) {
            preferences.maxDailySafetyMultiplier = maxDailySafetyMultiplier
        }

        if let currentBasalSafetyMultiplier = try? container.decode(Decimal.self, forKey: .currentBasalSafetyMultiplier) {
            preferences.currentBasalSafetyMultiplier = currentBasalSafetyMultiplier
        }

        if let autosensMax = try? container.decode(Decimal.self, forKey: .autosensMax) {
            preferences.autosensMax = autosensMax
        }

        if let autosensMin = try? container.decode(Decimal.self, forKey: .autosensMin) {
            preferences.autosensMin = autosensMin
        }

        if let smbDeliveryRatio = try? container.decode(Decimal.self, forKey: .smbDeliveryRatio) {
            preferences.smbDeliveryRatio = smbDeliveryRatio
        }

        if let rewindResetsAutosens = try? container.decode(Bool.self, forKey: .rewindResetsAutosens) {
            preferences.rewindResetsAutosens = rewindResetsAutosens
        }

        if let highTemptargetRaisesSensitivity = try? container.decode(Bool.self, forKey: .highTemptargetRaisesSensitivity) {
            preferences.highTemptargetRaisesSensitivity = highTemptargetRaisesSensitivity
        }

        if let lowTemptargetLowersSensitivity = try? container.decode(Bool.self, forKey: .lowTemptargetLowersSensitivity) {
            preferences.lowTemptargetLowersSensitivity = lowTemptargetLowersSensitivity
        }

        if let sensitivityRaisesTarget = try? container.decode(Bool.self, forKey: .sensitivityRaisesTarget) {
            preferences.sensitivityRaisesTarget = sensitivityRaisesTarget
        }

        if let resistanceLowersTarget = try? container.decode(Bool.self, forKey: .resistanceLowersTarget) {
            preferences.resistanceLowersTarget = resistanceLowersTarget
        }

        if let advTargetAdjustments = try? container.decode(Bool.self, forKey: .advTargetAdjustments) {
            preferences.advTargetAdjustments = advTargetAdjustments
        }

        if let exerciseMode = try? container.decode(Bool.self, forKey: .exerciseMode) {
            preferences.exerciseMode = exerciseMode
        }

        if let halfBasalExerciseTarget = try? container.decode(Decimal.self, forKey: .halfBasalExerciseTarget) {
            preferences.halfBasalExerciseTarget = halfBasalExerciseTarget
        }

        if let maxCOB = try? container.decode(Decimal.self, forKey: .maxCOB) {
            preferences.maxCOB = maxCOB
        }

        if let maxMealAbsorptionTime = try? container.decode(Decimal.self, forKey: .maxMealAbsorptionTime) {
            preferences.maxMealAbsorptionTime = maxMealAbsorptionTime
        }

        if let wideBGTargetRange = try? container.decode(Bool.self, forKey: .wideBGTargetRange) {
            preferences.wideBGTargetRange = wideBGTargetRange
        }

        if let skipNeutralTemps = try? container.decode(Bool.self, forKey: .skipNeutralTemps) {
            preferences.skipNeutralTemps = skipNeutralTemps
        }

        if let unsuspendIfNoTemp = try? container.decode(Bool.self, forKey: .unsuspendIfNoTemp) {
            preferences.unsuspendIfNoTemp = unsuspendIfNoTemp
        }

        if let min5mCarbimpact = try? container.decode(Decimal.self, forKey: .min5mCarbimpact) {
            preferences.min5mCarbimpact = min5mCarbimpact
        }

        if let remainingCarbsFraction = try? container.decode(Decimal.self, forKey: .remainingCarbsFraction) {
            preferences.remainingCarbsFraction = remainingCarbsFraction
        }

        if let remainingCarbsCap = try? container.decode(Decimal.self, forKey: .remainingCarbsCap) {
            preferences.remainingCarbsCap = remainingCarbsCap
        }

        if let enableUAM = try? container.decode(Bool.self, forKey: .enableUAM) {
            preferences.enableUAM = enableUAM
        }

        if let a52RiskEnable = try? container.decode(Bool.self, forKey: .a52RiskEnable) {
            preferences.a52RiskEnable = a52RiskEnable
        }

        if let enableSMBWithCOB = try? container.decode(Bool.self, forKey: .enableSMBWithCOB) {
            preferences.enableSMBWithCOB = enableSMBWithCOB
        }

        if let enableSMBWithTemptarget = try? container.decode(Bool.self, forKey: .enableSMBWithTemptarget) {
            preferences.enableSMBWithTemptarget = enableSMBWithTemptarget
        }

        if let enableSMBAlways = try? container.decode(Bool.self, forKey: .enableSMBAlways) {
            preferences.enableSMBAlways = enableSMBAlways
        }

        if let enableSMBAfterCarbs = try? container.decode(Bool.self, forKey: .enableSMBAfterCarbs) {
            preferences.enableSMBAfterCarbs = enableSMBAfterCarbs
        }

        if let allowSMBWithHighTemptarget = try? container.decode(Bool.self, forKey: .allowSMBWithHighTemptarget) {
            preferences.allowSMBWithHighTemptarget = allowSMBWithHighTemptarget
        }

        if let maxSMBBasalMinutes = try? container.decode(Decimal.self, forKey: .maxSMBBasalMinutes) {
            preferences.maxSMBBasalMinutes = maxSMBBasalMinutes
        }

        if let maxUAMSMBBasalMinutes = try? container.decode(Decimal.self, forKey: .maxUAMSMBBasalMinutes) {
            preferences.maxUAMSMBBasalMinutes = maxUAMSMBBasalMinutes
        }

        if let smbInterval = try? container.decode(Decimal.self, forKey: .smbInterval) {
            preferences.smbInterval = smbInterval
        }

        if let bolusIncrement = try? container.decode(Decimal.self, forKey: .bolusIncrement) {
            preferences.bolusIncrement = bolusIncrement
        }

        if let curve = try? container.decode(InsulinCurve.self, forKey: .curve) {
            preferences.curve = curve
        }

        if let useCustomPeakTime = try? container.decode(Bool.self, forKey: .useCustomPeakTime) {
            preferences.useCustomPeakTime = useCustomPeakTime
        }

        if let insulinPeakTime = try? container.decode(Decimal.self, forKey: .insulinPeakTime) {
            preferences.insulinPeakTime = insulinPeakTime
        }

        if let carbsReqThreshold = try? container.decode(Decimal.self, forKey: .carbsReqThreshold) {
            preferences.carbsReqThreshold = carbsReqThreshold
        }

        if let noisyCGMTargetMultiplier = try? container.decode(Decimal.self, forKey: .noisyCGMTargetMultiplier) {
            preferences.noisyCGMTargetMultiplier = noisyCGMTargetMultiplier
        }

        if let suspendZerosIOB = try? container.decode(Bool.self, forKey: .suspendZerosIOB) {
            preferences.suspendZerosIOB = suspendZerosIOB
        }

        if let maxDeltaBGthreshold = try? container.decode(Decimal.self, forKey: .maxDeltaBGthreshold) {
            preferences.maxDeltaBGthreshold = maxDeltaBGthreshold
        }

        if let adjustmentFactor = try? container.decode(Decimal.self, forKey: .adjustmentFactor) {
            preferences.adjustmentFactor = adjustmentFactor
        }

        if let adjustmentFactorSigmoid = try? container.decode(Decimal.self, forKey: .adjustmentFactorSigmoid) {
            preferences.adjustmentFactorSigmoid = adjustmentFactorSigmoid
        }

        if let sigmoid = try? container.decode(Bool.self, forKey: .sigmoid) {
            preferences.sigmoid = sigmoid
        }

        if let useNewFormula = try? container.decode(Bool.self, forKey: .useNewFormula) {
            preferences.useNewFormula = useNewFormula
        }

        if let useWeightedAverage = try? container.decode(Bool.self, forKey: .useWeightedAverage) {
            preferences.useWeightedAverage = useWeightedAverage
        }

        if let weightPercentage = try? container.decode(Decimal.self, forKey: .weightPercentage) {
            preferences.weightPercentage = weightPercentage
        }

        if let tddAdjBasal = try? container.decode(Bool.self, forKey: .tddAdjBasal) {
            preferences.tddAdjBasal = tddAdjBasal
        }

        if let enableSMB_high_bg = try? container.decode(Bool.self, forKey: .enableSMB_high_bg) {
            preferences.enableSMB_high_bg = enableSMB_high_bg
        }

        if let enableSMB_high_bg_target = try? container.decode(Decimal.self, forKey: .enableSMB_high_bg_target) {
            preferences.enableSMB_high_bg_target = enableSMB_high_bg_target
        }

        if let threshold_setting = try? container.decode(Decimal.self, forKey: .threshold_setting) {
            preferences.threshold_setting = threshold_setting
        }

        if let updateInterval = try? container.decode(Decimal.self, forKey: .updateInterval) {
            preferences.updateInterval = updateInterval
        }

        self = preferences
    }
}
