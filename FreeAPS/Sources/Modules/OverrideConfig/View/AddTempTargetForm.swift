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
    @State private var isUsingSlider = false

    @State private var didPressSave =
        false // only used for fixing the Disclaimer showing up after pressing save (after the state was resetted), maybe refactor this...
    @State private var shouldDisplayHint = false
    @State var hintDetent = PresentationDetent.large
    @State var selectedVerboseHint: String?
    @State var hintLabel: String?

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

    var isSliderEnabled: Bool {
        state.computeSliderHigh() > state.computeSliderLow()
    }

    var body: some View {
        NavigationView {
            Form {
                addTempTarget()
            }.scrollContentBackground(.hidden).background(color)
                .navigationTitle("Add Temp Target")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading: Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                })
                .alert(
                    "Start Temp Target",
                    isPresented: $showAlert,
                    actions: {
                        Button("Cancel", role: .cancel) { state.isTempTargetEnabled = false }
                        Button("Start Temp Target", role: .destructive) {
                            Task {
                                didPressSave.toggle()
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
                .sheet(isPresented: $shouldDisplayHint) {
                    SettingInputHintView(
                        hintDetent: $hintDetent,
                        shouldDisplayHint: $shouldDisplayHint,
                        hintLabel: hintLabel ?? "",
                        hintText: selectedVerboseHint ?? "",
                        sheetTitle: "Help"
                    )
                }
        }
    }

    @ViewBuilder private func addTempTarget() -> some View {
        Section(
            header: Text("Configure Temp Target"),
            content: {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("Enter Name (optional)", text: $state.tempTargetName)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Target")
                    Spacer()
                    TextFieldWithToolBar(text: $state.tempTargetTarget, placeholder: "0", numberFormatter: glucoseFormatter)
                        .onChange(of: state.tempTargetTarget) { _ in
                            state.percentage = Double(state.computeAdjustedPercentage() * 100)
                        }
                    Text(state.units.rawValue).foregroundColor(.secondary)
                }

                HStack {
                    Text("Duration")
                    Spacer()
                    TextFieldWithToolBar(text: $state.tempTargetDuration, placeholder: "0", numberFormatter: formatter)
                    Text("minutes").foregroundColor(.secondary)
                }
                DatePicker("Date", selection: $state.date)
            }
        ).listRowBackground(Color.chart)

        if isSliderEnabled && state.tempTargetTarget != 0 {
            if state.tempTargetTarget > 100 {
                Section {
                    VStack(alignment: .leading) {
                        Text("Raised Sensitivity:")
                            .font(.footnote)
                            .fontWeight(.bold)
                        Text("Insulin reduced to \(formattedPercentage(state.percentage))% of regular amount.")
                            .font(.footnote)
                            .lineLimit(1)
                    }
                }.listRowBackground(Color.tabBar)
                Section {
                    VStack {
                        Toggle("Adjust Sensitivity", isOn: $state.didAdjustSens).padding(.top)
                        HStack(alignment: .top) {
                            Text(
                                "Temp Target raises Sensitivity. Further adjust if desired!"
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = "Adjust Sensitivity for high Temp Target "
                                    selectedVerboseHint =
                                        "You have enabled High TempTarget Raises Sensitivity in Target Behaviour settings. Therefore current high Temp Target of \(state.tempTargetTarget) would raise your sensitivity, hence reduce Insulin dosing to \(formattedPercentage(state.percentage)) % of regular amount. This can be adjusted to another desired Insulin percentage!"
                                    shouldDisplayHint.toggle()
                                },
                                label: {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.top)
                    }.padding(.bottom)
                }.listRowBackground(Color.chart)
            } else if state.tempTargetTarget < 100 {
                Section {
                    VStack(alignment: .leading) {
                        Text("Lowered Sensitivity:")
                            .font(.footnote)
                            .fontWeight(.bold)
                        Text("Insulin increased to \(formattedPercentage(state.percentage))% of regular amount.")
                            .font(.footnote)
                            .lineLimit(1)
                    }
                }.listRowBackground(Color.tabBar)
                Section {
                    VStack {
                        Toggle("Adjust Insulin %", isOn: $state.didAdjustSens).padding(.top)
                        HStack(alignment: .top) {
                            Text(
                                "Temp Target lowers Sensitivity. Further adjust if desired!"
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = "Adjust Sensitivity for low Temp Target "
                                    selectedVerboseHint =
                                        "You have enabled Low TempTarget Lowers Sensitivity in Target Behaviour settings and set autosens Max > 1. Therefore current low Temp Target of \(state.tempTargetTarget) would lower your sensitivity, hence increase Insulin dosing to \(formattedPercentage(state.percentage)) % of regular amount. This can be adjusted to another desired Insulin percentage!"
                                    shouldDisplayHint.toggle()
                                },
                                label: {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.top)
                    }.padding(.bottom)
                }.listRowBackground(Color.chart)
            }

            if state.didAdjustSens && state.tempTargetTarget != 100 {
                Section {
                    VStack {
                        Text("\(Int(state.percentage)) % Insulin")
                            .foregroundColor(isUsingSlider ? .orange : Color.tabBar)
                            .font(.largeTitle)
                        Slider(
                            value: $state.percentage,
                            in: state.computeSliderLow() ... state.computeSliderHigh(),
                            step: 5
                        ) {} minimumValueLabel: {
                            Text("\(state.computeSliderLow(), specifier: "%.0f")%")
                        } maximumValueLabel: {
                            Text("\(state.computeSliderHigh(), specifier: "%.0f")%")
                        } onEditingChanged: { editing in
                            isUsingSlider = editing
                            state.halfBasalTarget = Decimal(state.computeHalfBasalTarget())
                        }
                        .disabled(!isSliderEnabled)

                        Divider()
                        HStack {
                            Text(
                                state
                                    .units == .mgdL ?
                                    "Half Basal Exercise Target at: \(state.computeHalfBasalTarget().formatted(.number.precision(.fractionLength(0)))) mg/dl" :
                                    "Half Basal Exercise Target at: \(state.computeHalfBasalTarget().asMmolL.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))) mmol/L"
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }.listRowBackground(Color.chart)
            }
        }

        // TODO: with iOS 17 we can change the body content wrapper from FORM to LIST and apply the .listSpacing modifier to make this all nice and small.
        Section {
            Button(action: {
                showAlert.toggle()
            }, label: {
                Text("Enact Temp Target")

            })
                .disabled(state.tempTargetDuration == 0)
                .frame(maxWidth: .infinity, alignment: .center)
                .tint(.white)
        }.listRowBackground(state.tempTargetDuration == 0 ? Color(.systemGray4) : Color(.systemBlue))

        Section {
            Button(action: {
                Task {
                    didPressSave.toggle()
                    await state.saveTempTargetPreset()
                    dismiss()
                }
            }, label: {
                Text("Save as Preset")

            })
                .disabled(state.tempTargetDuration == 0)
                .frame(maxWidth: .infinity, alignment: .center)
                .tint(.white)
        }.listRowBackground(state.tempTargetDuration == 0 ? Color(.systemGray4) : Color(.orange))
    }

    private func formattedPercentage(_ value: Double) -> String {
        let percentageNumber = NSNumber(value: value)
        return formatter.string(from: percentageNumber) ?? "\(value)"
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
