import Foundation
import SwiftUI

struct AddTempTargetForm: View {
    @StateObject var state: OverrideConfig.StateModel
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @State private var displayPickerDuration: Bool = false
    @State private var durationHours = 0
    @State private var durationMinutes = 0
    @State private var targetStep: Decimal = 5
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
            List {
                addTempTarget()
                saveButton
            }
            .listSectionSpacing(10)
            .listRowSpacing(10)
            .padding(.top, 30)
            .ignoresSafeArea(edges: .top)
            .scrollContentBackground(.hidden).background(color)
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
            }
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? "",
                    sheetTitle: "Help"
                )
            }
            .onAppear { targetStep = state.units == .mgdL ? 5 : 9 }
        }
    }

    @ViewBuilder private func addTempTarget() -> some View {
        Section {
            let pad: CGFloat = 3
            HStack {
                Text("Name")
                Spacer()
                TextField("Enter Name (optional)", text: $state.tempTargetName)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, pad)
            DatePicker("Date", selection: $state.date)
            VStack {
                HStack {
                    Text("Duration")
                    Spacer()
                    Text(formatHrMin(Int(state.tempTargetDuration)))
                        .foregroundColor(!displayPickerDuration ? .primary : .accentColor)
                }
                .padding(.vertical, pad)
                .onTapGesture {
                    displayPickerDuration.toggle()
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
            VStack {
                HStack {
                    Text("Target Glucose")
                    Spacer()
                    Text(formattedGlucose(glucose: state.tempTargetTarget))
                        .foregroundColor(!displayPickerTarget ? .primary : .accentColor)
                }
                .padding(.vertical, pad)
                .onTapGesture {
                    displayPickerTarget.toggle()
                }
                if displayPickerTarget {
                    HStack {
                        // Radio buttons and text on the left side
                        VStack(alignment: .leading) {
                            // Radio buttons for step iteration
                            let stepChoices: [Decimal] = state.units == .mgdL ? [1, 5] : [1, 9]
                            ForEach(stepChoices, id: \.self) { step in
                                RadioButton(
                                    isSelected: targetStep == step,
                                    label: "\(state.units == .mgdL ? step : step.asMmolL) \(state.units.rawValue)"
                                ) {
                                    targetStep = step
                                    state.tempTargetTarget = roundTargetToStep(state.tempTargetTarget, targetStep)
                                }
                                .padding(.top, 10)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Spacer()

                        // Picker on the right side
                        Picker(selection: Binding(
                            get: { roundTargetToStep(state.tempTargetTarget, targetStep) },
                            set: { state.tempTargetTarget = $0 }
                        ), label: Text("")) {
                            ForEach(
                                generateTargetPickerValues(),
                                id: \.self
                            ) { glucose in
                                Text(formattedGlucose(glucose: glucose))
                                    .tag(glucose)
                            }
                        }
                        .pickerStyle(WheelPickerStyle())
                        .frame(maxWidth: .infinity)
                        .onChange(of: state.tempTargetTarget) { _ in
                            state.percentage = Double(state.computeAdjustedPercentage() * 100)
                        }
                    }
                }
            }
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
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.vertical, pad)
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
                        }
                        .padding(.vertical, pad)
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
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.vertical, pad)
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
                        }
                        .padding(.vertical, pad)
                    }.listRowBackground(Color.chart)
                }

                if state.didAdjustSens && state.tempTargetTarget != 100 {
                    Section {
                        VStack {
                            Text("\(Int(state.percentage)) % Insulin")
                                .foregroundColor(isUsingSlider ? .orange : Color.tabBar)
                                .font(.title3)
                                .fontWeight(.bold)
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
                                .minimumScaleFactor(0.8)
                                .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                        .padding(.vertical, pad)
                    }.listRowBackground(Color.chart)
                }
            }
        }.listRowBackground(Color.chart)
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

    private func totalDurationInMinutes() -> Int {
        let durationTotal = (durationHours * 60) + durationMinutes
        return max(0, durationTotal)
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

    func generateTargetPickerValues() -> [Decimal] {
        var values: [Decimal] = []
        var currentValue: Double = 72
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

func formatHrMin(_ durationInMinutes: Int) -> String {
    let hours = durationInMinutes / 60
    let minutes = durationInMinutes % 60

    switch (hours, minutes) {
    case let (0, m):
        return "\(m) min"
    case let (h, 0):
        return "\(h) hr"
    default:
        return "\(hours) hr \(minutes) min"
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
