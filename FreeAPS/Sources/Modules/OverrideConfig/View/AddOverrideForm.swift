import Foundation
import SwiftUI

struct AddOverrideForm: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject var state: OverrideConfig.StateModel
    @State private var isEditing = false
    @State private var overrideTarget = false
    @Environment(\.colorScheme) var colorScheme
    @State private var showAlert = false
    @State private var alertString = ""

    @Environment(\.dismiss) var dismiss

    var color: LinearGradient {
        colorScheme == .dark ? LinearGradient(
            gradient: Gradient(colors: [
                Color.bgDarkBlue,
                Color.bgDarkerDarkBlue
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
            :
            LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                startPoint: .top,
                endPoint: .bottom
            )
    }

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if state.units == .mmolL {
            formatter.maximumFractionDigits = 1
        }
        formatter.roundingMode = .halfUp
        return formatter
    }

    private var alertMessage: String {
        let target: String = state.units == .mgdL ? "70-270 mg/dl" : "4-15 mmol/l"
        return "Please enter a valid target between" + " \(target)."
    }

    var body: some View {
        NavigationView {
            Form {
                addOverride()
            }.scrollContentBackground(.hidden).background(color)
                .navigationTitle("Add Override")
                .navigationBarItems(trailing: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                })
        }
    }

    @ViewBuilder private func addOverride() -> some View {
        Section {
            VStack {
                TextField("Name", text: $state.overrideName)
            }
        } header: {
            Text("Name")
        }.listRowBackground(Color.chart)

        Section {
            VStack {
                Spacer()
                Text("\(state.overrideSliderPercentage.formatted(.number)) %")
                    .foregroundColor(
                        state
                            .overrideSliderPercentage >= 130 ? .red :
                            (isEditing ? .orange : Color.tabBar)
                    )
                    .font(.largeTitle)
                Slider(
                    value: $state.overrideSliderPercentage,
                    in: 10 ... 200,
                    step: 1,
                    onEditingChanged: { editing in
                        isEditing = editing
                    }
                )
                Spacer()
                Toggle(isOn: $state.indefinite) {
                    Text("Enable Indefinitely")
                }
            }
            if !state.indefinite {
                HStack {
                    Text("Duration")
                    TextFieldWithToolBar(text: $state.overrideDuration, placeholder: "0", numberFormatter: formatter)
                    Text("minutes").foregroundColor(.secondary)
                }
            }

            HStack {
                Toggle(isOn: $state.shouldOverrideTarget) {
                    Text("Override Profile Target")
                }
            }
            if state.shouldOverrideTarget {
                HStack {
                    Text("Target Glucose")
                    TextFieldWithToolBar(text: $state.target, placeholder: "0", numberFormatter: glucoseFormatter)
                    Text(state.units.rawValue).foregroundColor(.secondary)
                }
            }
            HStack {
                Toggle(isOn: $state.advancedSettings) {
                    Text("More Options")
                }
            }
            if state.advancedSettings {
                HStack {
                    Toggle(isOn: Binding(
                        get: { state.smbIsOff },
                        set: { newValue in
                            state.smbIsOff = newValue
                            if newValue {
                                state.smbIsScheduledOff = false
                            }
                        }
                    )) {
                        Text("Disable SMBs")
                    }
                }
                HStack {
                    Toggle(isOn: Binding(
                        get: { state.smbIsScheduledOff },
                        set: { newValue in
                            state.smbIsScheduledOff = newValue
                            if newValue {
                                state.smbIsOff = false
                            }
                        }
                    )) {
                        Text("Schedule When SMBs Are Disabled")
                    }
                }

                if state.smbIsScheduledOff {
                    HStack {
                        Text("First Hour SMBs Are Disabled (24 hours)")
                        TextFieldWithToolBar(text: $state.start, placeholder: "0", numberFormatter: formatter)
                        Text("hour").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("First Hour SMBs Are Resumed (24 hours)")
                        TextFieldWithToolBar(text: $state.end, placeholder: "0", numberFormatter: formatter)
                        Text("hour").foregroundColor(.secondary)
                    }
                }
                HStack {
                    Toggle(isOn: $state.isfAndCr) {
                        Text("Change ISF and CR")
                    }
                }
                if !state.isfAndCr {
                    HStack {
                        Toggle(isOn: $state.isf) {
                            Text("Change ISF")
                        }
                    }
                    HStack {
                        Toggle(isOn: $state.cr) {
                            Text("Change CR")
                        }
                    }
                }
                if !state.smbIsOff {
                    HStack {
                        Text("SMB Minutes")
                        TextFieldWithToolBar(text: $state.smbMinutes, placeholder: "0", numberFormatter: formatter)
                        Text("minutes").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("UAM SMB Minutes")
                        TextFieldWithToolBar(text: $state.uamMinutes, placeholder: "0", numberFormatter: formatter)
                        Text("minutes").foregroundColor(.secondary)
                    }
                }
            }

            startAndSaveProfiles
        }
        header: { Text("Add custom Override") }
        footer: {
            Text(
                "Your profile ISF and CR will be inversly adjusted with the override percentage."
            )
        }.listRowBackground(Color.chart)
    }

    private var startAndSaveProfiles: some View {
        HStack {
            Button("Start New Override") {
                if !state.isInputInvalid(target: state.target) {
                    showAlert.toggle()

                    alertString = "\(state.overrideSliderPercentage.formatted(.number)) %, " +
                        (
                            state.overrideDuration > 0 || !state
                                .indefinite ?
                                (
                                    state
                                        .overrideDuration
                                        .formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) +
                                        " min."
                                ) :
                                NSLocalizedString(" infinite duration.", comment: "")
                        ) +
                        (
                            (state.target == 0 || !state.shouldOverrideTarget) ? "" :
                                (" Target: " + state.target.formatted() + " " + state.units.rawValue + ".")
                        )
                        +
                        (
                            state
                                .smbIsOff ?
                                NSLocalizedString(
                                    " SMBs are disabled either by schedule or during the entire duration.",
                                    comment: ""
                                ) : ""
                        )
                        +
                        "\n\n"
                        +
                        NSLocalizedString(
                            "Starting this override will change your profiles and/or your Target Glucose used for looping during the entire selected duration. Tapping ”Start Override” will start your new Override or edit your current active Override.",
                            comment: ""
                        )
                }
            }
            .disabled(unChanged())
            .buttonStyle(BorderlessButtonStyle())
            .font(.callout)
            .controlSize(.mini)
            .alert(
                "Start Override",
                isPresented: $showAlert,
                actions: {
                    Button("Cancel", role: .cancel) { state.isEnabled = false }
                    Button("Start Override", role: .destructive) {
                        Task {
                            if state.indefinite { state.overrideDuration = 0 }
                            state.isEnabled.toggle()
                            await state.saveCustomOverride()
                            await state.resetStateVariables()
                            dismiss()
                        }
                    }
                },
                message: {
                    Text(alertString)
                }
            )
            .alert(isPresented: $state.showInvalidTargetAlert) {
                Alert(
                    title: Text("Invalid Input"),
                    message: Text("\(state.alertMessage)"),
                    dismissButton: .default(Text("OK")) { state.showInvalidTargetAlert = false }
                )
            }
            Button {
                Task {
                    if !state.isInputInvalid(target: state.target) {
                        await state.saveOverridePreset()
                        dismiss()
                    }
                }
            }
            label: { Text("Save as Preset") }
                .tint(.orange)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .buttonStyle(BorderlessButtonStyle())
                .controlSize(.mini)
                .disabled(unChanged())
        }
    }

    private func unChanged() -> Bool {
        let defaultProfile = state.overrideSliderPercentage == 100 && !state.shouldOverrideTarget && !state.advancedSettings
        let noDurationSpecified = !state.indefinite && state.overrideDuration == 0
        let targetZeroWithOverride = state.shouldOverrideTarget && state.target == 0
        let allSettingsDefault = state.overrideSliderPercentage == 100 && !state.shouldOverrideTarget && !state.smbIsOff && !state
            .smbIsScheduledOff && state.smbMinutes == state.defaultSmbMinutes && state.uamMinutes == state.defaultUamMinutes

        return defaultProfile || noDurationSpecified || targetZeroWithOverride || allSettingsDefault
    }
}
