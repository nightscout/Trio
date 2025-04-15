//
//  AlgorithmSettingsStepView.swift
//  Trio
//
//  Created by Cengiz Deniz on 14.04.25
//
import SwiftUI

struct AlgorithmSettingsStepView: View {
    @Bindable var state: Onboarding.StateModel
    let substep: AlgorithmSettingsSubstep

    @State private var shouldDisplayPicker: Bool = false
    @State private var decimalPlaceholder: Decimal = 0.0
    @State private var booleanPlaceholder: Bool = false

    private let settingsProvider = PickerSettingsProvider.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch substep {
            case .autosensMax,
                 .autosensMin,
                 .rewindResetsAutosens:
                Text("Autosens")
                    .padding(.horizontal)
                    .font(.title3)
                    .bold()
                Text("Auto-sensitivity (Autosens) adjusts insulin delivery based on observed sensitivity or resistance.")
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal)
                    .foregroundStyle(Color.secondary)
            case .allowSMBWithHighTempTarget,
                 .enableSMBAfterCarbs,
                 .enableSMBAlways,
                 .enableSMBWithCOB,
                 .enableSMBWithHighGlucoseTarget,
                 .enableSMBWithTempTarget,
                 .enableUAM,
                 .maxDeltaGlucoseThreshold,
                 .maxSMBMinutes,
                 .maxUAMMinutes:
                Text("Super Micro Bolus (SMB)")
                    .padding(.horizontal)
                    .font(.title3)
                    .bold()
                Text(
                    "SMB is an oref algorithm feature that delivers small frequent boluses instead of temporary basals for faster glucose control."
                ).font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal)
                    .foregroundStyle(Color.secondary)
            case .halfBasalTarget,
                 .highTempTargetRaisesSensitivity,
                 .lowTempTargetLowersSensitivity,
                 .resistanceLowersTarget,
                 .sensitivityRaisesTarget:
                Text("Target Behavior")
                    .padding(.horizontal)
                    .font(.title3)
                    .bold()
                Text(
                    "Target Behavior allows you to adjust how temporary targets influence ISF, basal, and auto-targeting based on sensitivity or resistance."
                ).font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal)
                    .foregroundStyle(Color.secondary)
            }

            switch substep {
            case .autosensMin:
                algorithmSettingsInput(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: settingsProvider.settings.autosensMin,
                    decimalValue: $state.autosensMin,
                    booleanValue: $booleanPlaceholder,
                    type: .decimal
                )
            case .autosensMax:
                algorithmSettingsInput(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: settingsProvider.settings.autosensMax,
                    decimalValue: $state.autosensMax,
                    booleanValue: $booleanPlaceholder,
                    type: .decimal
                )
            case .rewindResetsAutosens:
                algorithmSettingsInput(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: nil,
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.rewindResetsAutosens,
                    type: .boolean
                )
            case .enableSMBAlways:
                algorithmSettingsInput(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: nil,
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.enableSMBAlways,
                    type: .boolean
                )
            case .enableSMBWithCOB:
                algorithmSettingsInput(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: nil,
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.enableSMBWithCOB,
                    type: .boolean
                )
            case .enableSMBWithTempTarget:
                algorithmSettingsInput(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: nil,
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.enableSMBWithTempTarget,
                    type: .boolean
                )
            case .enableSMBAfterCarbs:
                algorithmSettingsInput(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: nil,
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.enableSMBAfterCarbs,
                    type: .boolean
                )
            case .enableSMBWithHighGlucoseTarget:
                algorithmSettingsInput(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: nil,
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.enableSMBWithHighGlucoseTarget,
                    type: .boolean
                )
                if state.enableSMBWithHighGlucoseTarget {
                    algorithmSettingsInput(
                        label: String(localized: "High Glucose Target"),
                        displayPicker: $shouldDisplayPicker,
                        setting: settingsProvider.settings.enableSMB_high_bg_target,
                        decimalValue: $state.highGlucoseTarget,
                        booleanValue: $booleanPlaceholder,
                        type: .decimal
                    )
                }
            case .allowSMBWithHighTempTarget:
                algorithmSettingsInput(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: nil,
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.allowSMBWithHighTempTarget,
                    type: .boolean
                )
            case .enableUAM:
                algorithmSettingsInput(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: nil,
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.enableUAM,
                    type: .boolean
                )
            case .maxSMBMinutes:
                algorithmSettingsInput(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: settingsProvider.settings.maxSMBBasalMinutes,
                    decimalValue: $state.maxSMBMinutes,
                    booleanValue: $booleanPlaceholder,
                    type: .decimal
                )
            case .maxUAMMinutes:
                algorithmSettingsInput(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: settingsProvider.settings.maxUAMSMBBasalMinutes,
                    decimalValue: $state.maxUAMMinutes,
                    booleanValue: $booleanPlaceholder,
                    type: .decimal
                )
            case .maxDeltaGlucoseThreshold:
                algorithmSettingsInput(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: settingsProvider.settings.maxDeltaBGthreshold,
                    decimalValue: $state.maxDeltaGlucoseThreshold,
                    booleanValue: $booleanPlaceholder,
                    type: .decimal
                )
            case .highTempTargetRaisesSensitivity:
                algorithmSettingsInput(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: nil,
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.highTempTargetRaisesSensitivity,
                    type: .boolean
                )
            case .lowTempTargetLowersSensitivity:
                algorithmSettingsInput(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: nil,
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.lowTempTargetLowersSensitivity,
                    type: .boolean
                )
            case .sensitivityRaisesTarget:
                algorithmSettingsInput(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: nil,
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.sensitivityRaisesTarget,
                    type: .boolean
                )
            case .resistanceLowersTarget:
                algorithmSettingsInput(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: nil,
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.resistanceLowersTarget,
                    type: .boolean
                )
            case .halfBasalTarget:
                algorithmSettingsInput(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: settingsProvider.settings.halfBasalExerciseTarget,
                    decimalValue: $state.halfBasalTarget,
                    booleanValue: $booleanPlaceholder,
                    type: .decimal
                )
            }

            Text(substep.hint(units: state.units))
                .font(.body)
                .padding(.horizontal)
                .multilineTextAlignment(.leading)

            AnyView(substep.description(units: state.units))
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

    private func displayText(for substep: AlgorithmSettingsSubstep, decimalValue: Decimal, units: GlucoseUnits) -> Text {
        switch substep {
        case .autosensMax,
             .autosensMin,
             .maxDeltaGlucoseThreshold:
            return Text("\(decimalValue * 100) \(String(localized: "%", comment: "Percentage symbol"))")
        case .enableSMBWithHighGlucoseTarget,
             .halfBasalTarget:
            let displayValue = units == .mmolL ? decimalValue.asMmolL : decimalValue
            return Text("\(displayValue.description) \(units.rawValue)")
        case .maxSMBMinutes,
             .maxUAMMinutes:
            return Text("\(decimalValue) \(String(localized: "min", comment: "Minutes abbreviation"))")
        default:
            return Text("") // not needed, because input type is boolean
        }
    }
}
