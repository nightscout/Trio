import Foundation
import SwiftUI

struct EditTempTargetForm: View {
    @ObservedObject var tempTarget: TempTargetStored
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @StateObject var state: OverrideConfig.StateModel
    @State private var displayPickerDuration: Bool = false
    @State private var displayPickerTarget: Bool = false
    @State private var tempTargetSensitivityAdjustmentType: TempTargetSensitivityAdjustmentType = .standard
    @State private var durationHours = 0
    @State private var durationMinutes = 0
    @State private var targetStep: Decimal = 1
    @State private var name: String
    @State private var target: Decimal
    @State private var duration: Decimal
    @State private var date: Date
    @State private var halfBasalTarget: Decimal
    @State private var percentage: Decimal

    @State private var hasChanges = false
    @State private var showAlert = false
    @State private var isUsingSlider = false
    @State private var isPreset = false
    @State private var isEnabled = false

    init(tempTargetToEdit: TempTargetStored, state: OverrideConfig.StateModel) {
        tempTarget = tempTargetToEdit
        _state = StateObject(wrappedValue: state)
        _name = State(initialValue: tempTargetToEdit.name ?? "")
        _target = State(initialValue: tempTargetToEdit.target?.decimalValue ?? 0)
        _duration = State(initialValue: tempTargetToEdit.duration?.decimalValue ?? 0)
        _date = State(initialValue: tempTargetToEdit.date ?? Date())
        _halfBasalTarget = State(initialValue: tempTargetToEdit.halfBasalTarget?.decimalValue ?? 160)
        _isPreset = State(initialValue: tempTargetToEdit.isPreset)
        _isEnabled = State(initialValue: tempTargetToEdit.enabled)

        if let hbt = tempTargetToEdit.halfBasalTarget?.decimalValue {
            let H = hbt
            let T = tempTargetToEdit.target?.decimalValue ?? 100
            let calcPercentage = Double(state.computeAdjustedPercentage(usingHBT: H, usingTarget: T) * 100)
            _percentage = State(initialValue: Decimal(calcPercentage))
        } else { _percentage = State(initialValue: Decimal(100)) }
    }

    var color: LinearGradient {
        colorScheme == .dark ? LinearGradient(
            gradient: Gradient(colors: [
                Color.bgDarkBlue,
                Color.bgDarkerDarkBlue
            ]),
            startPoint: .top,
            endPoint: .bottom
        ) :
            LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                startPoint: .top,
                endPoint: .bottom
            )
    }

    var body: some View {
        NavigationView {
            List {
                editTempTarget()
                saveButton
            }
            .listSectionSpacing(10)
            .listRowSpacing(10)
            .padding(.top, 30)
            .ignoresSafeArea(edges: .top)
            .scrollContentBackground(.hidden).background(color)
            .navigationTitle("Edit Temp Target")
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
            .onAppear {
                if halfBasalTarget != state.settingHalfBasalTarget { tempTargetSensitivityAdjustmentType = .slider }
            }
        }
    }

    @ViewBuilder private func editTempTarget() -> some View {
        Group {
            Section {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("(Optional)", text: $name)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: name) {
                            hasChanges = true
                        }
                }
            }.listRowBackground(Color.chart)

            Section {
                DatePicker("Date", selection: $date)
                    .onChange(of: date) { hasChanges = true }
            }.listRowBackground(Color.chart)

            Section {
                VStack {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(formatHrMin(Int(duration)))
                            .foregroundColor(!displayPickerDuration ? .primary : .accentColor)
                    }
                    .onTapGesture {
                        displayPickerDuration = toggleScrollWheel(displayPickerDuration)
                    }
                    .onChange(of: duration) { hasChanges = true }

                    if displayPickerDuration {
                        HStack {
                            Picker(
                                selection: Binding(
                                    get: {
                                        Int(truncating: duration as NSNumber) / 60
                                    },
                                    set: {
                                        let minutes = Int(truncating: duration as NSNumber) % 60
                                        let totalMinutes = $0 * 60 + minutes
                                        duration = Decimal(totalMinutes)
                                        hasChanges = true
                                    }
                                ),
                                label: Text("")
                            ) {
                                ForEach(0 ..< 24) { hour in
                                    Text("\(hour) hr").tag(hour)
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)

                            Picker(
                                selection: Binding(
                                    get: {
                                        Int(truncating: duration as NSNumber) %
                                            60 // Convert Decimal to Int for modulus operation
                                    },
                                    set: {
                                        duration = Decimal((Int(truncating: duration as NSNumber) / 60) * 60 + $0)
                                        hasChanges = true
                                    }
                                ),
                                label: Text("")
                            ) {
                                ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { minute in
                                    Text("\(minute) min").tag(minute)
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)
                        }
                        .listRowSeparator(.hidden, edges: .top)
                    }
                }
            }.listRowBackground(Color.chart)

            Section {
                HStack {
                    // Picker on the right side
                    let settingsProvider = PickerSettingsProvider.shared
                    let glucoseSetting = PickerSetting(value: 0, step: targetStep, min: 80, max: 270, type: .glucose)
                    TargetPicker(
                        label: "Target Glucose",
                        selection: Binding(
                            get: { target },
                            set: { target = $0 }
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
                }
                .onChange(of: target) {
                    percentage = state.computeAdjustedPercentage(usingHBT: halfBasalTarget, usingTarget: target) * 100
                }
            }
            .listRowBackground(Color.chart)

            if target != state.normalTarget {
                let computedHalfBasalTarget = Decimal(
                    state
                        .computeHalfBasalTarget(usingTarget: target, usingPercentage: Double(percentage))
                )
                let sensHint = target > state.normalTarget ?
                    "Reducing all delivered insulin to \(formattedPercentage(Double(percentage)))%." :
                    "Increasing all delivered insulin by \(formattedPercentage(Double(percentage) - 100))%."

                if state.computeSliderLow(usingTarget: target) < state.computeSliderHigh(usingTarget: target) {
                    Section(
                        header: Text(sensHint)
                            .textCase(.none)
                            .foregroundStyle(colorScheme == .dark ? Color.orange : Color.accentColor),
                        content: {
                            VStack {
                                Picker("Sensitivity Adjustment", selection: $tempTargetSensitivityAdjustmentType) {
                                    ForEach(TempTargetSensitivityAdjustmentType.allCases, id: \.self) { option in
                                        Text(option.rawValue).tag(option)
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .onChange(of: tempTargetSensitivityAdjustmentType) { newValue in
                                        if newValue == .standard {
                                            halfBasalTarget = state.settingHalfBasalTarget
                                            percentage = (
                                                state
                                                    .computeAdjustedPercentage(usingHBT: halfBasalTarget, usingTarget: target) *
                                                    100
                                            )
                                        }
                                    }
                                }

                                if tempTargetSensitivityAdjustmentType == .slider {
                                    Text("\(formattedPercentage(Double(percentage))) % Insulin")
                                        .foregroundColor(isUsingSlider ? .orange : Color.tabBar)
                                        .font(.title3)
                                        .fontWeight(.bold)
                                    Slider(
                                        value: Binding(
                                            get: {
                                                Double(truncating: percentage as NSNumber)
                                            },
                                            set: { newValue in
                                                percentage = Decimal(newValue)
                                                hasChanges = true
                                                halfBasalTarget = Decimal(state.computeHalfBasalTarget(
                                                    usingTarget: target,
                                                    usingPercentage: Double(percentage)
                                                ))
                                            }
                                        ),
                                        in: Double(state.computeSliderLow(usingTarget: target)) ...
                                            Double(state.computeSliderHigh(usingTarget: target)),
                                        step: 5
                                    ) {}
                                    minimumValueLabel: {
                                        Text("\(state.computeSliderLow(usingTarget: target), specifier: "%.0f")%")
                                    }
                                    maximumValueLabel: {
                                        Text("\(state.computeSliderHigh(usingTarget: target), specifier: "%.0f")%")
                                    }

                                    Divider()

                                    HStack {
                                        Text(
                                            "Half Basal Exercise Target:"
                                        )
                                        Spacer()
                                        Text(formattedGlucose(glucose: computedHalfBasalTarget))
                                    }.foregroundStyle(.primary)
                                }
                            }.padding(.vertical, 10)
                        }
                    )
                    .listRowBackground(Color.chart)
                    .padding(.top, -10)
                }
            }
        }
    }

    private var saveButton: some View {
        HStack {
            Spacer()
            Button(action: {
                if !state.isInputInvalid(target: target) {
                    saveChanges()

                    do {
                        guard let moc = tempTarget.managedObjectContext else { return }
                        guard moc.hasChanges else { return }
                        try moc.save()

                        if let currentActiveTempTarget = state.currentActiveTempTarget {
                            Task {
                                // TODO: - Creating a Run entry is probably needed for Overrides as well and the reason for "jumping" Overrides?
                                // Disable previous active Temp Targets
                                await state.disableAllActiveOverrides(
                                    except: currentActiveTempTarget.objectID,
                                    createOverrideRunEntry: false
                                )

                                // If the temp target which currently gets edited is enabled, then store it to the Temp Target JSON so that oref uses it
                                if isEnabled {
                                    let tempTarget = TempTarget(
                                        name: name,
                                        createdAt: Date(),
                                        targetTop: target,
                                        targetBottom: target,
                                        duration: duration,
                                        enteredBy: TempTarget.manual,
                                        reason: TempTarget.custom,
                                        isPreset: isPreset ? true : false,
                                        enabled: isEnabled ? true : false,
                                        halfBasalTarget: halfBasalTarget
                                    )

                                    // Store to TempTargetStorage so that oref uses the edited Temp target
                                    state.saveTempTargetToStorage(tempTargets: [tempTarget])
                                }

                                // Update view
                                state.updateLatestTempTargetConfiguration()
                            }
                        }

                        hasChanges = false
                        presentationMode.wrappedValue.dismiss()
                    } catch {
                        debugPrint("Failed to Edit Temp Target")
                    }
                }
            }, label: {
                Text("Save")
            })
                .disabled(!hasChanges)
                .frame(maxWidth: .infinity, alignment: .center)
                .tint(.white)

            Spacer()
        }.listRowBackground(hasChanges ? Color(.systemBlue) : Color(.systemGray4))
    }

    private func saveChanges() {
        tempTarget.name = name
        tempTarget.target = NSDecimalNumber(decimal: target)
        tempTarget.duration = NSDecimalNumber(decimal: duration)
        tempTarget.date = date
        tempTarget.isUploadedToNS = false
        tempTarget.halfBasalTarget = NSDecimalNumber(decimal: halfBasalTarget)
    }

    private func toggleScrollWheel(_ toggle: Bool) -> Bool {
        displayPickerDuration = false
        displayPickerTarget = false
        return !toggle
    }

    private func resetValues() {
        name = tempTarget.name ?? ""
        target = tempTarget.target?.decimalValue ?? 0
        duration = tempTarget.duration?.decimalValue ?? 0
        date = tempTarget.date ?? Date()
    }

    private func totalDurationInMinutes() -> Int {
        let durationTotal = (durationHours * 60) + durationMinutes
        return max(0, durationTotal)
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
        if state.units == .mmolL {
            formatter.maximumFractionDigits = 1
        } else {
            formatter.maximumFractionDigits = 0
        }
        formatter.roundingMode = .halfUp
        return formatter
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
}
