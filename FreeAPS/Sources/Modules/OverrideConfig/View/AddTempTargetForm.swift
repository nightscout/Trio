import Foundation
import SwiftUI

struct AddTempTargetForm: View {
    // settings for picker steps
    let smallMgdL = 1.0
    let bigMgdL = 5.0
    let smallMmolL = 0.1 / 0.0555
    let bigMmolL = 0.5 / 0.0555
    init(state: OverrideConfig.StateModel) {
        _state = StateObject(wrappedValue: state)
        _targetStep = State(initialValue: state.units == .mgdL ? bigMgdL : bigMmolL)
    }

    @State var toggleBigStepOn = true

    @StateObject var state: OverrideConfig.StateModel
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @State private var targetStep: Double
    @State private var displayPickerTarget: Bool = false
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
                saveButton
            }.scrollContentBackground(.hidden).background(color)
                .navigationTitle("Add Temp Target")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading: Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                })
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
        let pad: CGFloat = 3
        VStack {
            HStack {
                Text("Name")
                Spacer()
                TextField("(Optional)", text: $state.overrideName).multilineTextAlignment(.trailing)
            }
            .padding(.vertical, pad)
        }
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
                    Text("Duration")
                    Spacer()
                    TextFieldWithToolBar(text: $state.tempTargetDuration, placeholder: "0", numberFormatter: formatter)
                    Text("minutes").foregroundColor(.secondary)
                }
                VStack {
                    HStack {
                        Text("Target Glucose")
                        Spacer()
                        Text(formattedGlucose(glucose: state.tempTargetTarget))
                            .foregroundColor(!displayPickerTarget ? .primary : .tabBar)
                    }
                    .padding(.vertical, pad)
                    .onTapGesture {
                        displayPickerTarget.toggle()
                    }
                    if displayPickerTarget {
                        HStack {
                            VStack(alignment: .leading) {
                                // Toggle for step iteration
                                VStack {
                                    Text(formattedGlucose(glucose: Decimal(state.units == .mgdL ? smallMgdL : smallMmolL)))
                                        .tag(Int(state.units == .mgdL ? smallMgdL : smallMmolL))
                                        .foregroundColor(toggleBigStepOn ? .primary : .tabBar)
                                    ZStack {
                                        Group {
                                            Capsule()
                                                .frame(width: 22, height: 40)
                                                .foregroundColor(Color.loopGray)
                                            ZStack {
                                                Circle()
                                                    .frame(width: 20, height: 22)
                                                Image(systemName: toggleBigStepOn ? "forward.circle.fill" : "play.circle.fill")
                                                    .foregroundStyle(Color.white, Color.tabBar)
                                            }
                                            .shadow(color: .black.opacity(0.14), radius: 4, x: 0, y: 2)
                                            .offset(y: toggleBigStepOn ? 9 : -9)
                                            .padding(12)
                                        }
                                    }
                                    .onTapGesture {
                                        // Toggling between small and big step
                                        toggleBigStepOn.toggle()
                                        targetStep = toggleBigStepOn ? (state.units == .mgdL ? bigMgdL : bigMmolL) :
                                            (state.units == .mgdL ? smallMgdL : smallMmolL)
                                        roundTargetToStep() // Ensure rounding happens after step change
                                    }
                                    Text(formattedGlucose(glucose: Decimal(state.units == .mgdL ? bigMgdL : bigMmolL)))
                                        .tag(Int(state.units == .mgdL ? bigMgdL : bigMmolL))
                                        .foregroundColor(toggleBigStepOn ? .tabBar : .primary)
                                }
                                .padding(.top, 10)
                            }
                            .frame(maxWidth: .infinity)

                            Spacer()

                            // Picker on the right side
                            Picker(
                                selection: Binding(
                                    get: { Int(truncating: state.tempTargetTarget as NSNumber) },
                                    set: { state.tempTargetTarget = Decimal($0) }
                                ), label: Text("")
                            ) {
                                ForEach(
                                    Array(stride(from: 80, through: 270, by: targetStep)),
                                    id: \.self
                                ) { glucose in
                                    Text(formattedGlucose(glucose: Decimal(glucose)))
                                        .tag(Int(glucose))
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    DatePicker("Date", selection: $state.date)
                }
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
                                "Half Basal Exercise Target at: \(formattedGlucose(glucose: Decimal(state.computeHalfBasalTarget())))"
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
//        Section {
//            Button(action: {
//                showAlert.toggle()
//            }, label: {
//                Text("Enact Temp Target")
//
//            })
//                .disabled(state.tempTargetDuration == 0)
//                .frame(maxWidth: .infinity, alignment: .center)
//                .tint(.white)
//        }.listRowBackground(state.tempTargetDuration == 0 ? Color(.systemGray4) : Color(.systemBlue))
//
//        Section {
//            Button(action: {
//                Task {
//                    didPressSave.toggle()
//                    await state.saveTempTargetPreset()
//                    dismiss()
//                }
//            }, label: {
//                Text("Save as Preset")
//
//            })
//                .disabled(state.tempTargetDuration == 0)
//                .frame(maxWidth: .infinity, alignment: .center)
//                .tint(.white)
//        }.listRowBackground(state.tempTargetDuration == 0 ? Color(.systemGray4) : Color(.orange))
    }

    private func isTempTargetInvalid() -> (Bool, String?) {
        let noDurationSpecified = state.tempTargetDuration == 0
        let targetZero = state.tempTargetTarget < 80

        if noDurationSpecified {
            return (true, "Set a duration!")
        }

        if targetZero {
            return (
                true,
                "\(state.units == .mgdL ? "80 " : "4.4 ")" + state.units.rawValue + " needed as min. Glucose Target!"
            )
        }

        return (false, nil)
    }

    private var saveButton: some View {
        let (isInvalid, errorMessage) = isTempTargetInvalid()
        let noNameSpecified = state.tempTargetName == ""

        return Group {
            Section(
                header:
                HStack {
                    Spacer()
                    Text(errorMessage ?? "").textCase(nil)
                        .foregroundColor(colorScheme == .dark ? .orange : .accentColor)
                    Spacer()
                },
                content: {
                    Button(action: {
                        Task {
                            if noNameSpecified { state.tempTargetName = "Custom Target" }
                            didPressSave.toggle()
                            state.isTempTargetEnabled.toggle()
                            await state.saveCustomTempTarget()
                            await state.resetTempTargetState()
                            dismiss()
                        }
                    }, label: {
                        Text("Enact Temp Target")
                    })
                        .disabled(isInvalid)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .tint(.white)
                }
            ).listRowBackground(isInvalid ? Color(.systemGray4) : Color(.systemBlue))

            Section {
                Button(action: {
                    Task {
                        if noNameSpecified { state.tempTargetName = "Custom Target" }
                        didPressSave.toggle()
                        await state.saveTempTargetPreset()
                        dismiss()
                    }
                }, label: {
                    Text("Save as Preset")

                })
                    .disabled(isInvalid)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .tint(.white)
            }
            .listRowBackground(
                isInvalid ? Color(.systemGray4) : Color.secondary
            )
        }
    }

    private func formattedPercentage(_ value: Double) -> String {
        let percentageNumber = NSNumber(value: value)
        return formatter.string(from: percentageNumber) ?? "\(value)"
    }

    private func formattedGlucose(glucose: Decimal) -> String {
        let formattedValue: String
        if state.units == .mgdL {
            formattedValue = glucoseFormatter.string(from: glucose as NSDecimalNumber) ?? "\(glucose)"
        } else {
            formattedValue = glucose.formattedAsMmolL
        }
        return "\(formattedValue) \(state.units.rawValue)"
    }

    private func roundTargetToStep() {
        // Check if tempTargetTarget is not divisible by the selected step
        if let tempTarget = state.tempTargetTarget as? Double,
           tempTarget.truncatingRemainder(dividingBy: targetStep) != 0
        {
            let roundedValue: Double

            if state.tempTargetTarget > 100 {
                // Round down to the nearest valid step away from 100
                let stepCount = (Double(state.tempTargetTarget) - 100) / targetStep
                roundedValue = 100 + floor(stepCount) * targetStep
            } else {
                // Round up to the nearest valid step away from 100
                let stepCount = (100 - Double(state.tempTargetTarget)) / targetStep
                roundedValue = 100 - floor(stepCount) * targetStep
            }

            // Ensure the value stays higher than 79
            state.tempTargetTarget = Decimal(max(80, roundedValue))
        }
    }
}

struct RadioButton: View {
    var isSelected: Bool
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: {
            action()
        }) {
            HStack {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                Text(label) // Add label inside the button to make it tappable
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
