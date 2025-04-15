//
//  AlgorithmSubstepView.swift
//  Trio
//
//  Created by Cengiz Deniz on 15.04.25.
//
import SwiftUI

struct AlgorithmSubstepView<Substep: AlgorithmSubstepProtocol & RawRepresentable>: View where Substep.RawValue == Int {
    @Bindable var state: Onboarding.StateModel
    let substep: Substep

    @State private var shouldDisplayPicker: Bool = false
    @State private var decimalPlaceholder: Decimal = 0.0
    @State private var booleanPlaceholder: Bool = false

    private let settingsProvider = PickerSettingsProvider.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(substep.title)
                .padding(.horizontal)
                .font(.title3)
                .bold()
            Text(substep.hint(units: state.units))
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .padding(.horizontal)
                .foregroundStyle(Color.secondary)

            if let step = substep.toAlgorithmSubstep() {
                switch step {
                case .autosensMin:
                    algorithmSettingsInput(
                        label: step.title,
                        displayPicker: $shouldDisplayPicker,
                        setting: settingsProvider.settings.autosensMin,
                        decimalValue: $state.autosensMin,
                        booleanValue: $booleanPlaceholder,
                        type: OnboardingInputSectionType.decimal
                    )
                case .autosensMax:
                    algorithmSettingsInput(
                        label: substep.title,
                        displayPicker: $shouldDisplayPicker,
                        setting: settingsProvider.settings.autosensMax,
                        decimalValue: $state.autosensMax,
                        booleanValue: $booleanPlaceholder,
                        type: OnboardingInputSectionType.decimal
                    )
                case .rewindResetsAutosens:
                    algorithmSettingsInput(
                        label: substep.title,
                        displayPicker: $shouldDisplayPicker,
                        setting: nil,
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.rewindResetsAutosens,
                        type: OnboardingInputSectionType.boolean
                    )
                case .enableSMBAlways:
                    algorithmSettingsInput(
                        label: substep.title,
                        displayPicker: $shouldDisplayPicker,
                        setting: nil,
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.enableSMBAlways,
                        type: OnboardingInputSectionType.boolean
                    )
                case .enableSMBWithCOB:
                    algorithmSettingsInput(
                        label: substep.title,
                        displayPicker: $shouldDisplayPicker,
                        setting: nil,
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.enableSMBWithCOB,
                        type: OnboardingInputSectionType.boolean
                    )
                case .enableSMBWithTempTarget:
                    algorithmSettingsInput(
                        label: substep.title,
                        displayPicker: $shouldDisplayPicker,
                        setting: nil,
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.enableSMBWithTempTarget,
                        type: OnboardingInputSectionType.boolean
                    )
                case .enableSMBAfterCarbs:
                    algorithmSettingsInput(
                        label: substep.title,
                        displayPicker: $shouldDisplayPicker,
                        setting: nil,
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.enableSMBAfterCarbs,
                        type: OnboardingInputSectionType.boolean
                    )
                case .enableSMBWithHighGlucoseTarget:
                    algorithmSettingsInput(
                        label: substep.title,
                        displayPicker: $shouldDisplayPicker,
                        setting: nil,
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.enableSMBWithHighGlucoseTarget,
                        type: OnboardingInputSectionType.boolean
                    )
                    if state.enableSMBWithHighGlucoseTarget {
                        algorithmSettingsInput(
                            label: String(localized: "High Glucose Target"),
                            displayPicker: $shouldDisplayPicker,
                            setting: settingsProvider.settings.enableSMB_high_bg_target,
                            decimalValue: $state.highGlucoseTarget,
                            booleanValue: $booleanPlaceholder,
                            type: OnboardingInputSectionType.decimal
                        )
                    }
                case .allowSMBWithHighTempTarget:
                    algorithmSettingsInput(
                        label: substep.title,
                        displayPicker: $shouldDisplayPicker,
                        setting: nil,
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.allowSMBWithHighTempTarget,
                        type: OnboardingInputSectionType.boolean
                    )
                case .enableUAM:
                    algorithmSettingsInput(
                        label: substep.title,
                        displayPicker: $shouldDisplayPicker,
                        setting: nil,
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.enableUAM,
                        type: OnboardingInputSectionType.boolean
                    )
                case .maxSMBMinutes:
                    algorithmSettingsInput(
                        label: substep.title,
                        displayPicker: $shouldDisplayPicker,
                        setting: settingsProvider.settings.maxSMBBasalMinutes,
                        decimalValue: $state.maxSMBMinutes,
                        booleanValue: $booleanPlaceholder,
                        type: OnboardingInputSectionType.decimal
                    )
                case .maxUAMMinutes:
                    algorithmSettingsInput(
                        label: substep.title,
                        displayPicker: $shouldDisplayPicker,
                        setting: settingsProvider.settings.maxUAMSMBBasalMinutes,
                        decimalValue: $state.maxUAMMinutes,
                        booleanValue: $booleanPlaceholder,
                        type: OnboardingInputSectionType.decimal
                    )
                case .maxDeltaGlucoseThreshold:
                    algorithmSettingsInput(
                        label: substep.title,
                        displayPicker: $shouldDisplayPicker,
                        setting: settingsProvider.settings.maxDeltaBGthreshold,
                        decimalValue: $state.maxDeltaGlucoseThreshold,
                        booleanValue: $booleanPlaceholder,
                        type: OnboardingInputSectionType.decimal
                    )
                case .highTempTargetRaisesSensitivity:
                    algorithmSettingsInput(
                        label: substep.title,
                        displayPicker: $shouldDisplayPicker,
                        setting: nil,
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.highTempTargetRaisesSensitivity,
                        type: OnboardingInputSectionType.boolean
                    )
                case .lowTempTargetLowersSensitivity:
                    algorithmSettingsInput(
                        label: substep.title,
                        displayPicker: $shouldDisplayPicker,
                        setting: nil,
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.lowTempTargetLowersSensitivity,
                        type: OnboardingInputSectionType.boolean
                    )
                case .sensitivityRaisesTarget:
                    algorithmSettingsInput(
                        label: substep.title,
                        displayPicker: $shouldDisplayPicker,
                        setting: nil,
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.sensitivityRaisesTarget,
                        type: OnboardingInputSectionType.boolean
                    )
                case .resistanceLowersTarget:
                    algorithmSettingsInput(
                        label: substep.title,
                        displayPicker: $shouldDisplayPicker,
                        setting: nil,
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.resistanceLowersTarget,
                        type: OnboardingInputSectionType.boolean
                    )
                case .halfBasalTarget:
                    algorithmSettingsInput(
                        label: substep.title,
                        displayPicker: $shouldDisplayPicker,
                        setting: settingsProvider.settings.halfBasalExerciseTarget,
                        decimalValue: $state.halfBasalTarget,
                        booleanValue: $booleanPlaceholder,
                        type: OnboardingInputSectionType.decimal
                    )
                }
            }

            substep.description(units: state.units).eraseToAnyView()
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .multilineTextAlignment(.leading)
        }
        .onDisappear {
            shouldDisplayPicker = false
        }
    }

    @ViewBuilder private func algorithmSettingsInput(
        label: String,
        displayPicker: Binding<Bool>,
        setting: PickerSetting?,
        decimalValue: Binding<Decimal>,
        booleanValue: Binding<Bool>,
        type: OnboardingInputSectionType
    ) -> some View {
        VStack {
            switch type {
            case .boolean:
                Toggle(isOn: booleanValue) {
                    Text(label)
                }.tint(Color.accentColor)
            case .decimal:
                Group {
                    HStack {
                        Text(label)
                        Spacer()
                        displayText(for: substep, decimalValue: decimalValue.wrappedValue, units: state.units)
                            .foregroundColor(!displayPicker.wrappedValue ? .primary : .accentColor)
                            .onTapGesture {
                                displayPicker.wrappedValue.toggle()
                            }
                    }

                    if displayPicker.wrappedValue {
                        Picker(selection: decimalValue, label: Text(label)) {
                            if let setting = setting {
                                ForEach(
                                    settingsProvider.generatePickerValues(from: setting, units: state.units),
                                    id: \.self
                                ) { value in
                                    displayText(for: substep, decimalValue: value, units: state.units).tag(value)
                                }
                            }
                        }
                        .pickerStyle(WheelPickerStyle())
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding()
        .background(Color.chart.opacity(0.65))
        .cornerRadius(10)
    }

    private func displayText(for substep: Substep, decimalValue: Decimal, units: GlucoseUnits) -> Text {
        guard let step = substep.toAlgorithmSubstep() else {
            return Text(decimalValue.description)
        }

        switch step {
        case .autosensMax,
             .autosensMin,
             .maxDeltaGlucoseThreshold:
            return Text("\(decimalValue * 100) \(String(localized: "%"))")
        case .enableSMBWithHighGlucoseTarget,
             .halfBasalTarget:
            let displayValue = units == .mmolL ? decimalValue.asMmolL : decimalValue
            return Text("\(displayValue.description) \(units.rawValue)")
        case .maxSMBMinutes,
             .maxUAMMinutes:
            return Text("\(decimalValue) \(String(localized: "min"))")
        default:
            return Text("") // not needed, because input type is boolean
        }
    }
}
