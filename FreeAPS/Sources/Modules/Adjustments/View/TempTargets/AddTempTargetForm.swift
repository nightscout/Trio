import Foundation
import SwiftUI

struct AddTempTargetForm: View {
    @StateObject var state: Adjustments.StateModel
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss
    @State private var displayPickerDuration: Bool = false
    @State private var displayPickerTarget: Bool = false
    @State private var tempTargetSensitivityAdjustmentType: TempTargetSensitivityAdjustmentType = .standard
    @State private var durationHours = 0
    @State private var durationMinutes = 0
    @State private var targetStep: Decimal = 5
    @State private var showAlert = false
    @State private var showPresetAlert = false
    @State private var alertString = ""
    @State private var isUsingSlider = false
    @State private var hasChanges = false

    @State private var didPressSave =
        false // only used for fixing the Disclaimer showing up after pressing save (after the state was resetted), maybe refactor this...
    @State private var shouldDisplayHint = false
    @State var hintDetent = PresentationDetent.large
    @State var selectedVerboseHint: String?
    @State var hintLabel: String?
    var isCustomizedAdjustSens: Bool = false

    var body: some View {
        NavigationView {
            List {
                addTempTarget()
                saveButton
            }
            .listSectionSpacing(10)
            .padding(.top, 30)
            .ignoresSafeArea(edges: .top)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Add Temp Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }, label: {
                        Text("Cancel")
                    })
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        action: {
                            state.isHelpSheetPresented.toggle()
                        },
                        label: {
                            Image(systemName: "questionmark.circle")
                        }
                    )
                }
            }
            .onAppear {
                targetStep = state.units == .mgdL ? 5 : 9
                state.tempTargetTarget = state.normalTarget
            }
            .sheet(isPresented: $state.isHelpSheetPresented) {
                NavigationStack {
                    List {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "A Temporary Target replaces the current Target Glucose specified in Therapy settings."
                            )
                            Text(
                                "Depending on the Algorithm > Target Behavior settings, these temporary glucose targets can also raise Insulin Sensitivity for high targets or lower sensitivity for low targets."
                            )
                            Text(
                                "Furthermore, you could adjust that sensitivity change independently from the Half Basal Exercise Target specified in Algorithm > Target Behavior settings by deliberatly setting a customized Insulin Percentage for a Temp Target."
                            )
                            Text(
                                "A pre-condition to have Temp Targets adjust Sensitivity is that the respective Target Behavior settings High Temp Target Raises Sensitivity or Low Temp Target Lowers Sensitivity are set to enabled!"
                            )
                        }
                    }
                    .padding(.trailing, 10)
                    .navigationBarTitle("Help", displayMode: .inline)

                    Button { state.isHelpSheetPresented.toggle() }
                    label: { Text("Got it!").frame(maxWidth: .infinity, alignment: .center) }
                        .buttonStyle(.bordered)
                        .padding(.top)
                }
                .padding()
                .presentationDetents(
                    [.fraction(0.9), .large],
                    selection: $state.helpSheetDetent
                )
            }
        }
    }

    @ViewBuilder private func addTempTarget() -> some View {
        Group {
            Section {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("(Optional)", text: $state.tempTargetName)
                        .multilineTextAlignment(.trailing)
                }
            }.listRowBackground(Color.chart)

            Section {
                let settingsProvider = PickerSettingsProvider.shared
                let glucoseSetting = PickerSetting(value: 0, step: targetStep, min: 80, max: 200, type: .glucose)
                TargetPicker(
                    label: "Target Glucose",
                    selection: Binding(
                        get: { state.tempTargetTarget },
                        set: { state.tempTargetTarget = $0 }
                    ),
                    options: settingsProvider.generatePickerValues(
                        from: glucoseSetting,
                        units: state.units,
                        roundMinToStep: true
                    ),
                    units: state.units,
                    hasChanges: $hasChanges,
                    targetStep: $targetStep,
                    displayPickerTarget: $displayPickerTarget,
                    toggleScrollWheel: toggleScrollWheel
                )
                .onChange(of: state.tempTargetTarget) {
                    state.percentage = state.computeAdjustedPercentage()
                }
            }
            .listRowBackground(Color.chart)

            if state.tempTargetTarget != state.normalTarget {
                let computedHalfBasalTarget = Decimal(state.computeHalfBasalTarget())

                if state.isAdjustSensEnabled() {
                    Section(
                        footer: state.percentageDescription(state.percentage),
                        content: {
                            Picker("Sensitivity Adjustment", selection: $tempTargetSensitivityAdjustmentType) {
                                ForEach(TempTargetSensitivityAdjustmentType.allCases, id: \.self) { option in
                                    Text(option.rawValue).tag(option)
                                }
                                .pickerStyle(MenuPickerStyle())
                                .onChange(of: tempTargetSensitivityAdjustmentType) { _, newValue in
                                    if newValue == .standard {
                                        state.halfBasalTarget = state.settingHalfBasalTarget
                                        state.percentage = state.computeAdjustedPercentage()
                                    }
                                }
                            }

                            Text("\(formattedPercentage(state.percentage))% Insulin")
                                .foregroundColor(isUsingSlider ? .orange : Color.tabBar)
                                .font(.title3)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .center)

                            if tempTargetSensitivityAdjustmentType == .slider {
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
                                .listRowSeparator(.hidden, edges: .top)
                            }
                        }
                    )
                    .listRowBackground(Color.chart)
                }
            }

            Section {
                DatePicker("Start Time", selection: $state.date, in: Date.now...)
            }.listRowBackground(Color.chart)

            Section {
                VStack {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(state.formatHrMin(Int(state.tempTargetDuration)))
                            .foregroundColor(
                                !displayPickerDuration ?
                                    (state.tempTargetDuration > 0 ? .primary : .secondary) : .accentColor
                            )
                            .onTapGesture {
                                displayPickerDuration = toggleScrollWheel(displayPickerDuration)
                            }
                    }

                    if displayPickerDuration {
                        HStack {
                            Picker("Hours", selection: $durationHours) {
                                ForEach(0 ..< 24) { hour in
                                    Text("\(hour) hr").tag(hour)
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)
                            .onChange(of: durationHours) {
                                state.tempTargetDuration = Decimal(totalDurationInMinutes())
                            }

                            Picker("Minutes", selection: $durationMinutes) {
                                ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { minute in
                                    Text("\(minute) min").tag(minute)
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)
                            .onChange(of: durationMinutes) {
                                state.tempTargetDuration = Decimal(totalDurationInMinutes())
                            }
                        }
                    }
                }
            }.listRowBackground(Color.chart)
        }
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

    private func isSavePresetInvalid() -> (Bool, String?) {
        let (isTempTargetInvalid, tempTargetError) = isTempTargetInvalid()
        let isDateInFuture = state.date > Date()

        if isTempTargetInvalid {
            return (true, tempTargetError)
        }

        if isDateInFuture {
            return (true, "Presets can't be saved with a future date!")
        }

        return (false, nil)
    }

    private var saveButton: some View {
        let (isTempTargetInvalid, _) = isTempTargetInvalid()
        let (isSavePresetInvalid, savePresetError) = isSavePresetInvalid()
        let noNameSpecified = state.tempTargetName == ""
        return Group {
            Section(
                header:
                HStack {
                    Spacer()
                    Text(savePresetError ?? "").textCase(nil)
                        .foregroundColor(colorScheme == .dark ? .orange : .accentColor)
                    Spacer()
                },
                content: {
                    Button(action: {
                        Task {
                            if noNameSpecified { state.tempTargetName = "Custom Target" }
                            didPressSave.toggle()
                            await state.invokeSaveOfCustomTempTargets()
                            dismiss()
                        }
                    }, label: {
                        Text("Start Temp Target")
                    })
                        .disabled(isTempTargetInvalid)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .tint(.white)
                }
            ).listRowBackground(isTempTargetInvalid ? Color(.systemGray4) : Color(.systemBlue))

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
                    .disabled(isSavePresetInvalid)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .tint(.white)
            }

            .listRowBackground(
                isSavePresetInvalid ? Color(.systemGray4) : Color.secondary
            )
        }
    }

    private func totalDurationInMinutes() -> Int {
        let durationTotal = (durationHours * 60) + durationMinutes
        return max(0, durationTotal)
    }

    private func formattedPercentage(_ value: Double) -> String {
        let percentageNumber = NSNumber(value: value)
        return Formatter.integerFormatter.string(from: percentageNumber) ?? "\(value)"
    }

    private func formattedGlucose(glucose: Decimal) -> String {
        let formattedValue: String
        if state.units == .mgdL {
            formattedValue = Formatter.glucoseFormatter(for: state.units).string(from: glucose as NSDecimalNumber) ?? "\(glucose)"
        } else {
            formattedValue = glucose.formattedAsMmolL
        }
        return "\(formattedValue) \(state.units.rawValue)"
    }

    private func roundTargetToStep(_ target: Decimal, _ step: Decimal) -> Decimal {
        // Convert target and step to NSDecimalNumber
        guard let targetValue = NSDecimalNumber(decimal: target).doubleValue as Double?,
              let stepValue = NSDecimalNumber(decimal: step).doubleValue as Double?
        else {
            print("Failed to unwrap target or step as NSDecimalNumber")
            return target
        }

        // Perform the remainder check using truncatingRemainder
        let remainder = Decimal(targetValue.truncatingRemainder(dividingBy: stepValue))

        if remainder != 0 {
            // Calculate how much to adjust (up or down) based on the remainder
            let adjustment = step - remainder
            return target + adjustment
        }

        // Return the original target if no adjustment is needed
        return target
    }

    private func toggleScrollWheel(_ toggle: Bool) -> Bool {
        displayPickerDuration = false
        displayPickerTarget = false
        return !toggle
    }

    func generateTargetPickerValues() -> [Decimal] {
        var values: [Decimal] = []
        var currentValue: Double = 80 // lowest allowed TT in oref
        let step = Double(targetStep)

        // Adjust currentValue to be divisible by targetStep
        let remainder = currentValue.truncatingRemainder(dividingBy: step)
        if remainder != 0 {
            // Move currentValue up to the next value divisible by targetStep
            currentValue += (step - remainder)
        }

        // Now generate the picker values starting from currentValue
        while currentValue <= 270 {
            values.append(Decimal(currentValue))
            currentValue += step
        }

        // Glucose values are stored as mg/dl values, so Integers.
        // Filter out duplicate values when rounded to 1 decimal place.
        if state.units == .mmolL {
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
