import SwiftUI

class PickerSettingsProvider: ObservableObject {
    static let shared = PickerSettingsProvider()

    var settings = DecimalPickerSettings()

    private init() {} // Private init to enforce singleton pattern

    // Helper function to generate values for the picker
    func generatePickerValues(from setting: PickerSetting, units: GlucoseUnits) -> [Decimal] {
        var values: [Decimal] = []
        var currentValue = setting.min

        while currentValue <= setting.max {
            values.append(currentValue)
            currentValue += setting.step
        }

        // Glucose values are stored as mg/dl values, so Integers.
        // Filter out duplicate values when rounded to 1 decimal place.
        if units == .mmolL, setting.type == PickerSetting.PickerSettingType.glucose {
            // Use a Set to track unique values rounded to 1 decimal
            var uniqueRoundedValues = Set<String>()
            values = values.filter { value in
                let roundedValue = String(format: "%.1f", NSDecimalNumber(decimal: value.asMmolL).doubleValue)
                return uniqueRoundedValues.insert(roundedValue).inserted
            }
        }

        return values
    }
}

struct DecimalPickerSettings {
    var lowGlucose = PickerSetting(value: 70, step: 5, min: 40, max: 100, type: PickerSetting.PickerSettingType.glucose)
    var highGlucose = PickerSetting(value: 180, step: 5, min: 100, max: 400, type: PickerSetting.PickerSettingType.glucose)
    var carbsRequiredThreshold = PickerSetting(value: 10, step: 1, min: 0, max: 100, type: PickerSetting.PickerSettingType.gram)
    var individualAdjustmentFactor = PickerSetting(
        value: 0.5,
        step: 0.05,
        min: 0.1,
        max: 1.2,
        type: PickerSetting.PickerSettingType.factor
    )
    var high = PickerSetting(value: 180, step: 1, min: 100, max: 500, type: PickerSetting.PickerSettingType.glucose)
    var low = PickerSetting(value: 70, step: 1, min: 40, max: 100, type: PickerSetting.PickerSettingType.glucose)
    var maxCarbs = PickerSetting(value: 250, step: 5, min: 0, max: 300, type: PickerSetting.PickerSettingType.gram)
    var maxFat = PickerSetting(value: 250, step: 5, min: 0, max: 300, type: PickerSetting.PickerSettingType.gram)
    var maxProtein = PickerSetting(value: 250, step: 5, min: 0, max: 300, type: PickerSetting.PickerSettingType.gram)
    var overrideFactor = PickerSetting(value: 0.8, step: 0.05, min: 0.05, max: 1.5, type: PickerSetting.PickerSettingType.factor)
    var fattyMealFactor = PickerSetting(value: 0.7, step: 0.05, min: 0.05, max: 1, type: PickerSetting.PickerSettingType.factor)
    var sweetMealFactor = PickerSetting(value: 1, step: 0.05, min: 0.05, max: 2, type: PickerSetting.PickerSettingType.factor)
    var maxIOB = PickerSetting(value: 0, step: 1, min: 0, max: 20, type: PickerSetting.PickerSettingType.insulinUnit)
    var maxDailySafetyMultiplier = PickerSetting(
        value: 3,
        step: 0.1,
        min: 1,
        max: 5,
        type: PickerSetting.PickerSettingType.factor
    )
    var currentBasalSafetyMultiplier = PickerSetting(
        value: 4,
        step: 0.1,
        min: 1,
        max: 5,
        type: PickerSetting.PickerSettingType.factor
    )
    var autosensMax = PickerSetting(value: 1.2, step: 0.05, min: 0.5, max: 2, type: PickerSetting.PickerSettingType.factor)
    var autosensMin = PickerSetting(value: 0.7, step: 0.05, min: 0.5, max: 1, type: PickerSetting.PickerSettingType.factor)
    var smbDeliveryRatio = PickerSetting(value: 0.5, step: 0.05, min: 0.3, max: 0.7, type: PickerSetting.PickerSettingType.factor)
    var halfBasalExerciseTarget = PickerSetting(
        value: 160,
        step: 5,
        min: 100,
        max: 300,
        type: PickerSetting.PickerSettingType.glucose
    )
    var maxCOB = PickerSetting(value: 120, step: 5, min: 0, max: 300, type: PickerSetting.PickerSettingType.gram)
    var maxMealAbsorptionTime = PickerSetting(value: 6, step: 1, min: 4, max: 10, type: PickerSetting.PickerSettingType.hour)
    var min5mCarbimpact = PickerSetting(value: 8, step: 1, min: 1, max: 20, type: PickerSetting.PickerSettingType.glucose)
    var remainingCarbsFraction = PickerSetting(
        value: 1.0,
        step: 0.05,
        min: 0.5,
        max: 1,
        type: PickerSetting.PickerSettingType.factor
    )
    var remainingCarbsCap = PickerSetting(value: 90, step: 5, min: 0, max: 200, type: PickerSetting.PickerSettingType.gram)
    var maxSMBBasalMinutes = PickerSetting(value: 30, step: 5, min: 30, max: 180, type: PickerSetting.PickerSettingType.minute)
    var maxUAMSMBBasalMinutes = PickerSetting(value: 30, step: 5, min: 30, max: 180, type: PickerSetting.PickerSettingType.minute)
    var smbInterval = PickerSetting(value: 3, step: 1, min: 1, max: 10, type: PickerSetting.PickerSettingType.minute)
    var bolusIncrement = PickerSetting(
        value: 0.1,
        step: 0.05,
        min: 0.05,
        max: 1,
        type: PickerSetting.PickerSettingType.insulinUnit
    )
    var insulinPeakTime = PickerSetting(value: 75, step: 1, min: 35, max: 120, type: PickerSetting.PickerSettingType.minute)
    var carbsReqThreshold = PickerSetting(value: 1.0, step: 0.1, min: 0, max: 10, type: PickerSetting.PickerSettingType.gram)
    var noisyCGMTargetMultiplier = PickerSetting(
        value: 1.3,
        step: 0.05,
        min: 1,
        max: 2,
        type: PickerSetting.PickerSettingType.factor
    )
    var maxDeltaBGthreshold = PickerSetting(
        value: 0.2,
        step: 0.05,
        min: 0.1,
        max: 0.4,
        type: PickerSetting.PickerSettingType.factor
    )
    var adjustmentFactor = PickerSetting(value: 0.8, step: 0.05, min: 0.3, max: 1.5, type: PickerSetting.PickerSettingType.factor)
    var adjustmentFactorSigmoid = PickerSetting(
        value: 0.5,
        step: 0.05,
        min: 0.1,
        max: 2,
        type: PickerSetting.PickerSettingType.factor
    )
    var weightPercentage = PickerSetting(value: 0.35, step: 0.05, min: 0.05, max: 1, type: PickerSetting.PickerSettingType.factor)
    var enableSMB_high_bg_target = PickerSetting(
        value: 110,
        step: 1,
        min: 70,
        max: 200,
        type: PickerSetting.PickerSettingType.glucose
    )
    var threshold_setting = PickerSetting(value: 60, step: 1, min: 60, max: 120, type: PickerSetting.PickerSettingType.glucose)
    var updateInterval = PickerSetting(value: 20, step: 5, min: 1, max: 60, type: PickerSetting.PickerSettingType.minute)
    var delay = PickerSetting(value: 60, step: 10, min: 60, max: 120, type: PickerSetting.PickerSettingType.minute)
    var minuteInterval = PickerSetting(value: 30, step: 5, min: 10, max: 60, type: PickerSetting.PickerSettingType.minute)
    var timeCap = PickerSetting(value: 8, step: 1, min: 5, max: 12, type: PickerSetting.PickerSettingType.hour)
    var hours = PickerSetting(value: 6, step: 0.5, min: 2, max: 24, type: PickerSetting.PickerSettingType.hour)
    var dia = PickerSetting(value: 10, step: 0.5, min: 5, max: 10, type: PickerSetting.PickerSettingType.hour)
    var maxBolus = PickerSetting(value: 10, step: 0.5, min: 0.5, max: 30, type: PickerSetting.PickerSettingType.insulinUnit)
    var maxBasal = PickerSetting(
        value: 10,
        step: 0.5,
        min: 0.5,
        max: 30,
        type: PickerSetting.PickerSettingType.insulinUnitPerHour
    )
}

struct PickerSetting {
    var value: Decimal
    var step: Decimal
    var min: Decimal
    var max: Decimal
    var type: PickerSettingType

    enum PickerSettingType {
        case glucose
        case factor
        case gram
        case insulinUnit
        case insulinUnitPerHour
        case minute
        case hour
    }
}
