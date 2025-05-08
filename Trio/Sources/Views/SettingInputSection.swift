import SwiftUI

struct SettingInputSection<VerboseHint: View>: View {
    enum SettingInputSectionType: Equatable {
        case decimal(String)
        case boolean
        case conditionalDecimal(String)

        static func == (lhs: SettingInputSectionType, rhs: SettingInputSectionType) -> Bool {
            switch (lhs, rhs) {
            case (.boolean, .boolean):
                return true
            case let (.decimal(lhsValue), .decimal(rhsValue)):
                return lhsValue == rhsValue
            case let (.conditionalDecimal(lhsValue), .conditionalDecimal(rhsValue)):
                return lhsValue == rhsValue
            default:
                return false
            }
        }
    }

    @Binding var decimalValue: Decimal
    @Binding var booleanValue: Bool
    @Binding var shouldDisplayHint: Bool
    @Binding var selectedVerboseHint: (any View)?

    var units: GlucoseUnits
    var type: SettingInputSectionType
    var label: String
    var conditionalLabel: String?
    var miniHint: String
    var verboseHint: VerboseHint
    var headerText: String?
    var footerText: String?
    var isToggleDisabled: Bool = false
    var miniHintColor: Color = .secondary

    @ObservedObject private var pickerSettingsProvider = PickerSettingsProvider.shared
    @State private var displayPicker: Bool = false
    @State private var displayConditionalPicker: Bool = false

    var body: some View {
        Section(
            content: {
                VStack {
                    switch type {
                    case let .decimal(key):
                        if let setting = getPickerSetting(for: key) {
                            pickerView(
                                label: label,
                                displayPicker: $displayPicker,
                                setting: setting,
                                decimalValue: $decimalValue
                            )
                        }

                    case .boolean:
                        toggleView(label: label, isOn: $booleanValue)
                            .disabled(isToggleDisabled)

                    case let .conditionalDecimal(key):
                        VStack {
                            toggleView(label: label, isOn: $booleanValue)
                            if booleanValue, let setting = getPickerSetting(for: key) {
                                pickerView(
                                    label: conditionalLabel ?? label,
                                    displayPicker: $displayConditionalPicker,
                                    setting: setting,
                                    decimalValue: $decimalValue
                                )
                            }
                        }
                    }

                    hintSection(
                        miniHint: miniHint,
                        shouldDisplayHint: $shouldDisplayHint,
                        verboseHint: verboseHint,
                        miniHintColor: miniHintColor
                    )
                }
            },
            header: { headerText.map(Text.init) },
            footer: { footerText.map(Text.init) }
        ).listRowBackground(Color.chart)
    }

    // Helper function to retrieve PickerSetting based on key
    private func getPickerSetting(for key: String) -> PickerSetting? {
        switch key {
        case "lowGlucose":
            return pickerSettingsProvider.settings.lowGlucose
        case "highGlucose":
            return pickerSettingsProvider.settings.highGlucose
        case "carbsRequiredThreshold":
            return pickerSettingsProvider.settings.carbsRequiredThreshold
        case "individualAdjustmentFactor":
            return pickerSettingsProvider.settings.individualAdjustmentFactor
        case "delay":
            return pickerSettingsProvider.settings.delay
        case "timeCap":
            return pickerSettingsProvider.settings.timeCap
        case "minuteInterval":
            return pickerSettingsProvider.settings.minuteInterval
        case "high":
            return pickerSettingsProvider.settings.high
        case "low":
            return pickerSettingsProvider.settings.low
        case "hours":
            return pickerSettingsProvider.settings.hours
        case "maxCarbs":
            return pickerSettingsProvider.settings.maxCarbs
        case "maxMealAbsorptionTime":
            return pickerSettingsProvider.settings.maxMealAbsorptionTime
        case "maxFat":
            return pickerSettingsProvider.settings.maxFat
        case "maxProtein":
            return pickerSettingsProvider.settings.maxProtein
        case "overrideFactor":
            return pickerSettingsProvider.settings.overrideFactor
        case "fattyMealFactor":
            return pickerSettingsProvider.settings.fattyMealFactor
        case "sweetMealFactor":
            return pickerSettingsProvider.settings.sweetMealFactor
        case "maxIOB":
            return pickerSettingsProvider.settings.maxIOB
        case "maxDailySafetyMultiplier":
            return pickerSettingsProvider.settings.maxDailySafetyMultiplier
        case "currentBasalSafetyMultiplier":
            return pickerSettingsProvider.settings.currentBasalSafetyMultiplier
        case "autosensMax":
            return pickerSettingsProvider.settings.autosensMax
        case "autosensMin":
            return pickerSettingsProvider.settings.autosensMin
        case "smbDeliveryRatio":
            return pickerSettingsProvider.settings.smbDeliveryRatio
        case "halfBasalExerciseTarget":
            return pickerSettingsProvider.settings.halfBasalExerciseTarget
        case "maxCOB":
            return pickerSettingsProvider.settings.maxCOB
        case "min5mCarbimpact":
            return pickerSettingsProvider.settings.min5mCarbimpact
        case "remainingCarbsFraction":
            return pickerSettingsProvider.settings.remainingCarbsFraction
        case "remainingCarbsCap":
            return pickerSettingsProvider.settings.remainingCarbsCap
        case "maxSMBBasalMinutes":
            return pickerSettingsProvider.settings.maxSMBBasalMinutes
        case "maxUAMSMBBasalMinutes":
            return pickerSettingsProvider.settings.maxUAMSMBBasalMinutes
        case "smbInterval":
            return pickerSettingsProvider.settings.smbInterval
        case "bolusIncrement":
            return pickerSettingsProvider.settings.bolusIncrement
        case "insulinPeakTime":
            return pickerSettingsProvider.settings.insulinPeakTime
        case "carbsReqThreshold":
            return pickerSettingsProvider.settings.carbsReqThreshold
        case "noisyCGMTargetMultiplier":
            return pickerSettingsProvider.settings.noisyCGMTargetMultiplier
        case "maxDeltaBGthreshold":
            return pickerSettingsProvider.settings.maxDeltaBGthreshold
        case "adjustmentFactor":
            return pickerSettingsProvider.settings.adjustmentFactor
        case "adjustmentFactorSigmoid":
            return pickerSettingsProvider.settings.adjustmentFactorSigmoid
        case "weightPercentage":
            return pickerSettingsProvider.settings.weightPercentage
        case "enableSMB_high_bg_target":
            return pickerSettingsProvider.settings.enableSMB_high_bg_target
        case "threshold_setting":
            return pickerSettingsProvider.settings.threshold_setting
        case "updateInterval":
            return pickerSettingsProvider.settings.updateInterval
        case "dia":
            return pickerSettingsProvider.settings.dia
        case "maxBolus":
            return pickerSettingsProvider.settings.maxBolus
        case "maxBasal":
            return pickerSettingsProvider.settings.maxBasal
        default:
            return nil
        }
    }

    private func pickerView(
        label: String,
        displayPicker: Binding<Bool>,
        setting: PickerSetting,
        decimalValue: Binding<Decimal>
    ) -> some View {
        VStack {
            HStack {
                Text(label)
                Spacer()
                displayText(for: setting, decimalValue: decimalValue.wrappedValue)
                    .foregroundColor(!displayPicker.wrappedValue ? .primary : .accentColor)
                    .onTapGesture {
                        displayPicker.wrappedValue.toggle()
                    }
            }.padding(.top)

            if displayPicker.wrappedValue {
                Picker(selection: decimalValue, label: Text(label)) {
                    ForEach(pickerSettingsProvider.generatePickerValues(from: setting, units: self.units), id: \.self) { value in
                        displayText(for: setting, decimalValue: value).tag(value)
                    }
                }
                .pickerStyle(WheelPickerStyle())
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func displayText(for setting: PickerSetting, decimalValue: Decimal) -> Text {
        switch setting.type {
        case .glucose:
            let displayValue = units == .mmolL ? decimalValue.asMmolL : decimalValue
            return Text("\(displayValue.description) \(units.rawValue)")
        case .factor:
            return Text("\(decimalValue * 100) \(String(localized: "%", comment: "Percentage symbol"))")
        case .insulinUnit:
            return Text("\(decimalValue) \(String(localized: "U", comment: "Insulin unit abbreviation"))")
        case .insulinUnitPerHour:
            return Text("\(decimalValue) \(String(localized: "U/hr", comment: "Insulin unit per hour abbreviation"))")
        case .gram:
            return Text("\(decimalValue) \(String(localized: "g", comment: "Gram abbreviation"))")
        case .minute:
            return Text("\(decimalValue) \(String(localized: "min", comment: "Minutes abbreviation"))")
        case .hour:
            return Text("\(decimalValue) \(String(localized: "hr", comment: "Hours abbreviation"))")
        }
    }

    private func toggleView(label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Toggle(isOn: isOn) {
                Text(label)
            }
        }.padding(.top)
    }

    private func hintSection(
        miniHint: String,
        shouldDisplayHint: Binding<Bool>,
        verboseHint: VerboseHint,
        miniHintColor: Color = .secondary
    ) -> some View {
        HStack(alignment: .center) {
            Text(miniHint)
                .font(.footnote)
                .foregroundColor(miniHintColor)
                .lineLimit(nil)
            Spacer()
            Button(action: {
                shouldDisplayHint.wrappedValue.toggle()
                selectedVerboseHint = shouldDisplayHint.wrappedValue ? verboseHint : nil
            }) {
                HStack {
                    Image(systemName: "questionmark.circle")
                }
            }
            .buttonStyle(BorderlessButtonStyle())
        }.padding(.vertical)
    }
}
