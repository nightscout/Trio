import Foundation
import SwiftUI

struct AddTempTargetForm: View {
    @StateObject var state: OverrideConfig.StateModel
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @State private var showAlert = false
    @State private var showPresetAlert = false
    @State private var alertString = ""

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
                addTempTarget()
            }.scrollContentBackground(.hidden).background(color)
                .navigationTitle("Add Temp Target")
                .navigationBarItems(trailing: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                })
                .alert(
                    "Start Temp Target",
                    isPresented: $showAlert,
                    actions: {
                        Button("Cancel", role: .cancel) { state.isTempTargetEnabled = false }
                        Button("Start Temp Target", role: .destructive) {
                            Task {
                                await setupAlertString()
                                state.isTempTargetEnabled.toggle()
                                await state.saveCustomTempTarget()
                                await state.resetTempTargetState()
                                dismiss()
                            }
                        }
                    },
                    message: {
                        Text(alertString)
                    }
                )
        }
    }

    @ViewBuilder private func addTempTarget() -> some View {
        Section {
            VStack {
                TextField("Name", text: $state.tempTargetName)
            }
        } header: {
            Text("Name")
        }.listRowBackground(Color.chart)

        Section {
            HStack {
                Text("Target")
                Spacer()
                TextFieldWithToolBar(text: $state.tempTargetTarget, placeholder: "0", numberFormatter: glucoseFormatter)
                Text(state.units.rawValue).foregroundColor(.secondary)
            }
            HStack {
                Text("Duration")
                Spacer()
                TextFieldWithToolBar(text: $state.tempTargetDuration, placeholder: "0", numberFormatter: formatter)
                Text("minutes").foregroundColor(.secondary)
            }
            DatePicker("Date", selection: $state.date)
            HStack {
                Button {
                    showAlert.toggle()
                }
                label: { Text("Enact") }
                    .disabled(state.tempTargetDuration == 0)
                    .buttonStyle(BorderlessButtonStyle())
                    .font(.callout)
                    .controlSize(.mini)

                Button {
                    Task {
                        await state.saveTempTargetPreset()
                    }
                }
                label: { Text("Save as preset") }
                    .disabled(state.tempTargetDuration == 0)
                    .tint(.orange)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .buttonStyle(BorderlessButtonStyle())
                    .controlSize(.mini)
            }
        } header: {
            Text("Add Custom Temp Target")
        }.listRowBackground(Color.chart)
    }

    private func setupAlertString() async {
        alertString =
            (
                state.tempTargetDuration > 0 ?
                    (
                        state
                            .tempTargetDuration
                            .formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) +
                            " min."
                    ) :
                    NSLocalizedString(" infinite duration.", comment: "")
            ) +
            (
                state.tempTargetTarget == 0 ? "" :
                    (" Target: " + state.tempTargetTarget.formatted() + " " + state.units.rawValue + ".")
            )
            +
            "\n\n"
            +
            NSLocalizedString(
                "Starting this Temp Target will change your profiles and/or your Target Glucose used for looping during the entire selected duration. Tapping ”Start Temp Target” will start your new Temp Target or edit your current active Temp Target.",
                comment: ""
            )
    }
}
