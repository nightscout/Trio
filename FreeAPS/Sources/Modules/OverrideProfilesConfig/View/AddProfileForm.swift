import Foundation
import SwiftUI

struct AddProfileForm: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject var state: OverrideProfilesConfig.StateModel
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

    var body: some View {
        NavigationView {
            Form {
                addProfile()
            }.scrollContentBackground(.hidden).background(color)
                .navigationTitle("Add Profile")
                .navigationBarItems(trailing: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                })
        }
    }

    @ViewBuilder private func addProfile() -> some View {
        Section {
            VStack {
                TextField("Name", text: $state.profileName)
            }
        } header: {
            Text("Name")
        }.listRowBackground(Color.chart)

        Section {
            VStack {
                Spacer()
                Text("\(state.percentageProfiles.formatted(.number)) %")
                    .foregroundColor(
                        state
                            .percentageProfiles >= 130 ? .red :
                            (isEditing ? .orange : Color.tabBar)
                    )
                    .font(.largeTitle)
                Slider(
                    value: $state.percentageProfiles,
                    in: 10 ... 200,
                    step: 1,
                    onEditingChanged: { editing in
                        isEditing = editing
                    }
                )
                Spacer()
                Toggle(isOn: $state._indefinite) {
                    Text("Enable indefinitely")
                }
            }
            if !state._indefinite {
                HStack {
                    Text("Duration")
                    TextFieldWithToolBar(text: $state.durationProfile, placeholder: "0", numberFormatter: formatter)
                    Text("minutes").foregroundColor(.secondary)
                }
            }

            HStack {
                Toggle(isOn: $state.override_target) {
                    Text("Override Profile Target")
                }
            }
            if state.override_target {
                HStack {
                    Text("Target Glucose")
                    TextFieldWithToolBar(text: $state.target, placeholder: "0", numberFormatter: glucoseFormatter)
                    Text(state.units.rawValue).foregroundColor(.secondary)
                }
            }
            HStack {
                Toggle(isOn: $state.advancedSettings) {
                    Text("More options")
                }
            }
            if state.advancedSettings {
                HStack {
                    Toggle(isOn: $state.smbIsOff) {
                        Text("Disable SMBs")
                    }
                }
                HStack {
                    Toggle(isOn: $state.smbIsAlwaysOff) {
                        Text("Schedule when SMBs are Off")
                    }.disabled(!state.smbIsOff)
                }
                if state.smbIsAlwaysOff {
                    HStack {
                        Text("First Hour SMBs are Off (24 hours)")
                        TextFieldWithToolBar(text: $state.start, placeholder: "0", numberFormatter: formatter)
                        Text("hour").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Last Hour SMBs are Off (24 hours)")
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

            startAndSaveProfiles
        }
        header: { Text("Add custom Override") }
        footer: {
            Text(
                "Your profile basal insulin will be adjusted with the override percentage and your profile ISF and CR will be inversly adjusted with the percentage."
            )
        }.listRowBackground(Color.chart)
    }

    private var startAndSaveProfiles: some View {
        HStack {
            Button("Start new Profile") {
                showAlert.toggle()

                alertString = "\(state.percentageProfiles.formatted(.number)) %, " +
                    (
                        state.durationProfile > 0 || !state
                            ._indefinite ?
                            (
                                state
                                    .durationProfile
                                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) +
                                    " min."
                            ) :
                            NSLocalizedString(" infinite duration.", comment: "")
                    ) +
                    (
                        (state.target == 0 || !state.override_target) ? "" :
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
                        "Starting this override will change your Profiles and/or your Target Glucose used for looping during the entire selected duration. Tapping ”Start Profile” will start your new profile or edit your current active profile.",
                        comment: ""
                    )
            }
            .disabled(unChanged())
            .buttonStyle(BorderlessButtonStyle())
            .font(.callout)
            .controlSize(.mini)
            .alert(
                "Start Profile",
                isPresented: $showAlert,
                actions: {
                    Button("Cancel", role: .cancel) { state.isEnabled = false }
                    Button("Start Profile", role: .destructive) {
                        Task {
                            if state._indefinite { state.durationProfile = 0 }
                            state.isEnabled.toggle()
                            await state.saveAsProfile()
                            await state.resetStateVariables()
                            dismiss()
                        }
                    }
                },
                message: {
                    Text(alertString)
                }
            )
            Button {
                Task {
                    await state.savePreset()
                    dismiss()
                }
            }
            label: { Text("Save as Profile") }
                .tint(.orange)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .buttonStyle(BorderlessButtonStyle())
                .controlSize(.mini)
                .disabled(unChanged())
        }
    }

    private func unChanged() -> Bool {
        let isChanged = (
            state.percentageProfiles == 100 && !state.override_target && !state.smbIsOff && !state
                .advancedSettings
        ) ||
            (!state._indefinite && state.durationProfile == 0) || (state.override_target && state.target == 0) ||
            (
                state.percentageProfiles == 100 && !state.override_target && !state.smbIsOff && state.isf && state.cr && state
                    .smbMinutes == state.defaultSmbMinutes && state.uamMinutes == state.defaultUamMinutes
            )

        return isChanged
    }
}
