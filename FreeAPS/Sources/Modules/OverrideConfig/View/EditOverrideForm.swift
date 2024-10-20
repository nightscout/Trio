import Foundation
import SwiftUI

struct EditOverrideForm: View {
    @ObservedObject var override: OverrideStored
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @Bindable var state: OverrideConfig.StateModel

    @State private var name: String
    @State private var percentage: Double
    @State private var indefinite: Bool
    @State private var duration: Decimal
    @State private var target: Decimal?
    @State private var advancedSettings: Bool
    @State private var smbIsOff: Bool
    @State private var smbIsScheduledOff: Bool
    @State private var start: Decimal?
    @State private var end: Decimal?
    @State private var isfAndCr: Bool
    @State private var isf: Bool
    @State private var cr: Bool
    @State private var smbMinutes: Decimal?
    @State private var uamMinutes: Decimal?
    @State private var selectedIsfCrOption: IsfAndOrCrOptions
    @State private var selectedDisableSmbOption: DisableSmbOptions

    @State private var hasChanges = false
    @State private var isEditing = false
    @State private var target_override = false
    @State private var percentageStep: Int = 5
    @State private var displayPickerPercentage: Bool = false
    @State private var displayPickerDuration: Bool = false
    @State private var targetStep: Decimal = 5
    @State private var displayPickerTarget: Bool = false
    @State private var displayPickerDisableSmbSchedule: Bool = false
    @State private var displayPickerSmbMinutes: Bool = false

    init(overrideToEdit: OverrideStored, state: OverrideConfig.StateModel) {
        override = overrideToEdit
        _state = Bindable(wrappedValue: state)
        _name = State(initialValue: overrideToEdit.name ?? "")
        _percentage = State(initialValue: overrideToEdit.percentage)
        _indefinite = State(initialValue: overrideToEdit.indefinite)
        _duration = State(initialValue: overrideToEdit.duration?.decimalValue ?? 0)
        _target = State(initialValue: overrideToEdit.target?.decimalValue)
        _target_override = State(initialValue: overrideToEdit.target?.decimalValue != 0)
        _advancedSettings = State(initialValue: overrideToEdit.advancedSettings)
        _smbIsOff = State(initialValue: overrideToEdit.smbIsOff)
        _smbIsScheduledOff = State(initialValue: overrideToEdit.smbIsScheduledOff)
        _start = State(initialValue: overrideToEdit.start?.decimalValue)
        _end = State(initialValue: overrideToEdit.end?.decimalValue)
        _isfAndCr = State(initialValue: overrideToEdit.isfAndCr)
        _isf = State(initialValue: overrideToEdit.isf)
        _cr = State(initialValue: overrideToEdit.cr)
        _selectedIsfCrOption = State(
            initialValue: overrideToEdit.isfAndCr ? .isfAndCr
                : (overrideToEdit.isf ? .isf : (overrideToEdit.cr ? .cr : .nothing))
        )
        _selectedDisableSmbOption = State(
            initialValue: overrideToEdit.smbIsScheduledOff ? .disableOnSchedule
                : (overrideToEdit.smbIsOff ? .disable : .dontDisable)
        )
        _smbMinutes = State(initialValue: overrideToEdit.smbMinutes?.decimalValue)
        _uamMinutes = State(initialValue: overrideToEdit.uamMinutes?.decimalValue)
    }

    enum IsfAndOrCrOptions: String, CaseIterable {
        case isfAndCr = "ISF/CR"
        case isf = "ISF"
        case cr = "CR"
        case nothing = "None"
    }

    enum DisableSmbOptions: String, CaseIterable {
        case dontDisable = "Don't Disable"
        case disable = "Disable"
        case disableOnSchedule = "Disable on Schedule"
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

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    private var percentageSelection: Binding<Double> {
        Binding<Double>(
            get: {
                let value = floor(percentage / Double(percentageStep)) * Double(percentageStep)
                return max(10, min(value, 200))
            },
            set: {
                percentage = $0
                hasChanges = true
            }
        )
    }

    var body: some View {
        NavigationView {
            List {
                editOverride()
                saveButton
            }
            .listSectionSpacing(10)
            .listRowSpacing(10)
            .padding(.top, 30)
            .ignoresSafeArea(edges: .top)
            .scrollContentBackground(.hidden).background(color)
            .navigationTitle("Edit Override")
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
            .onAppear { targetStep = state.units == .mgdL ? 5 : 9 }
            .onDisappear {
                if !hasChanges {
                    // Reset UI changes
                    resetValues()
                }
            }
            .sheet(isPresented: $state.isHelpSheetPresented) {
                NavigationStack {
                    List {
                        Text(
                            "Lorem Ipsum Dolor Sit Amet"
                        )

                        Text(
                            "Lorem Ipsum Dolor Sit Amet"
                        )

                        Text(
                            "Lorem Ipsum Dolor Sit Amet"
                        )
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

    @ViewBuilder private func editOverride() -> some View {
        Section {
            let pad: CGFloat = 3
            if override.name != nil {
                VStack {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Name", text: $name)
                            .onChange(of: name) { hasChanges = true }
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, pad)
                }
            }

            VStack {
                Toggle(isOn: $indefinite) { Text("Enable Indefinitely") }
                    .padding(.vertical, pad)
                    .onChange(of: indefinite) { hasChanges = true }

                if !indefinite {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(formatHrMin(Int(truncating: duration as NSNumber)))
                            .foregroundColor(!displayPickerDuration ? .primary : .accentColor)
                    }
                    .padding(.vertical, pad)
                    .onTapGesture {
                        displayPickerDuration.toggle()
                    }

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
                    }
                }
            }

            // Percentage Picker
            VStack {
                HStack {
                    Text("Change Basal Rate by")
                    Spacer()
                    Text("\(percentage.formatted(.number)) %")
                        .foregroundColor(!displayPickerPercentage ? .primary : .accentColor)
                }
                .padding(.vertical, pad)
                .onTapGesture {
                    displayPickerPercentage.toggle()
                }

                if displayPickerPercentage {
                    HStack {
                        // Radio buttons and text on the left side
                        VStack(alignment: .leading) {
                            // Radio buttons for step iteration
                            ForEach([1, 5], id: \.self) { step in
                                RadioButton(isSelected: percentageStep == step, label: "\(step) %") {
                                    percentageStep = step
                                    percentage = OverrideConfig.StateModel.roundOverridePercentageToStep(percentage, step)
                                }
                                .padding(.top, 10)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Spacer()

                        // Picker on the right side
                        Picker(
                            selection: percentageSelection,
                            label: Text("")
                        ) {
                            ForEach(
                                Array(stride(from: 40.0, through: 150.0, by: Double(percentageStep))),
                                id: \.self
                            ) { percent in
                                Text("\(Int(percent)) %").tag(percent)
                            }
                        }
                        .pickerStyle(WheelPickerStyle())
                        .frame(maxWidth: .infinity)
                    }
                }

                // Picker for ISF/CR settings
                Picker("Also Change", selection: $selectedIsfCrOption) {
                    ForEach(IsfAndOrCrOptions.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .padding(.top, pad)
                .pickerStyle(MenuPickerStyle())
                .onChange(of: selectedIsfCrOption) { _, newValue in
                    switch newValue {
                    case .isfAndCr:
                        isfAndCr = true
                        isf = false
                        cr = false
                    case .isf:
                        isfAndCr = false
                        isf = true
                        cr = false
                    case .cr:
                        isfAndCr = false
                        isf = false
                        cr = true
                    case .nothing:
                        isfAndCr = false
                        isf = false
                        cr = false
                    }
                    hasChanges = true
                }
            }

            VStack {
                Toggle(isOn: $target_override) {
                    Text("Override Target")
                }
                .padding(.vertical, pad)
                .onChange(of: target_override) {
                    hasChanges = true
                }
                // Target Glucose Picker
                if target_override {
                    TargetPicker(
                        label: "Target Glucose",
                        selection: Binding(
                            get: { target ?? 100 },
                            set: { target = $0 }
                        ),
                        options: generateTargetPickerValues(),
                        units: state.units,
                        hasChanges: $hasChanges,
                        targetStep: $targetStep
                    )
                }
            }

            VStack {
                // Picker for Disable SMB settings
                Picker("Disable SMBs", selection: $selectedDisableSmbOption) {
                    ForEach(DisableSmbOptions.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .padding(.vertical, pad)
                .pickerStyle(MenuPickerStyle())
                .onChange(of: selectedDisableSmbOption) { _, newValue in
                    switch newValue {
                    case .dontDisable:
                        smbIsOff = false
                        smbIsScheduledOff = false
                    case .disable:
                        smbIsOff = true
                        smbIsScheduledOff = false
                    case .disableOnSchedule:
                        smbIsOff = false
                        smbIsScheduledOff = true
                    }
                    hasChanges = true
                }

                if smbIsScheduledOff {
                    // First Hour SMBs Are Disabled
                    HStack {
                        Text("From")
                        Spacer()
                        Text(
                            is24HourFormat() ? format24Hour(Int(truncating: start! as NSNumber)) + ":00" :
                                convertTo12HourFormat(Int(truncating: start! as NSNumber))
                        )
                        .foregroundColor(!displayPickerDisableSmbSchedule ? .primary : .accentColor)

                        Spacer()

                        Divider().frame(width: 1, height: 20)

                        Spacer()

                        Text("To")
                        Spacer()
                        Text(
                            is24HourFormat() ? format24Hour(Int(truncating: end! as NSNumber)) + ":00" :
                                convertTo12HourFormat(Int(truncating: end! as NSNumber))
                        )
                        .foregroundColor(!displayPickerDisableSmbSchedule ? .primary : .accentColor)
                    }
                    .padding(.vertical, pad)
                    .onTapGesture {
                        displayPickerDisableSmbSchedule.toggle()
                    }

                    if displayPickerDisableSmbSchedule {
                        HStack {
                            Picker(selection: Binding(
                                get: { Int(truncating: start! as NSNumber) },
                                set: {
                                    start = Decimal($0)
                                    hasChanges = true
                                }
                            ), label: Text("")) {
                                if is24HourFormat() {
                                    ForEach(0 ..< 24, id: \.self) { hour in
                                        Text(format24Hour(hour) + ":00").tag(hour)
                                    }
                                } else {
                                    ForEach(0 ..< 24, id: \.self) { hour in
                                        Text(convertTo12HourFormat(hour)).tag(hour)
                                    }
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)

                            Picker(selection: Binding(
                                get: { Int(truncating: end! as NSNumber) },
                                set: {
                                    end = Decimal($0)
                                    hasChanges = true
                                }
                            ), label: Text("")) {
                                if is24HourFormat() {
                                    ForEach(0 ..< 24, id: \.self) { hour in
                                        Text(format24Hour(hour) + ":00").tag(hour)
                                    }
                                } else {
                                    ForEach(0 ..< 24, id: \.self) { hour in
                                        Text(convertTo12HourFormat(hour)).tag(hour)
                                    }
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }

            if !smbIsOff {
                VStack {
                    Toggle(isOn: $advancedSettings) {
                        Text("Change Max SMB Minutes")
                    }
                    .padding(.vertical, pad)
                    .onChange(of: advancedSettings) { hasChanges = true }

                    if advancedSettings {
                        // SMB Minutes Picker
                        VStack {
                            HStack {
                                Text("SMB")
                                Spacer()
                                Text("\(smbMinutes?.formatted(.number) ?? "\(state.defaultSmbMinutes)") min")
                                    .foregroundColor(!displayPickerSmbMinutes ? .primary : .accentColor)

                                Spacer()

                                Divider().frame(width: 1, height: 20)

                                Spacer()

                                Text("UAM")
                                Spacer()
                                Text("\(uamMinutes?.formatted(.number) ?? "\(state.defaultUamMinutes)") min")
                                    .foregroundColor(!displayPickerSmbMinutes ? .primary : .accentColor)
                            }
                            .padding(.vertical, pad)
                            .onTapGesture {
                                displayPickerSmbMinutes.toggle()
                            }

                            if displayPickerSmbMinutes {
                                HStack {
                                    Picker(
                                        selection: Binding(
                                            get: { smbMinutes ?? state.defaultSmbMinutes },
                                            set: {
                                                smbMinutes = $0
                                                hasChanges = true
                                            }
                                        ),
                                        label: Text("")
                                    ) {
                                        ForEach(Array(stride(from: 0, through: 180, by: 5)), id: \.self) { minute in
                                            Text("\(minute) min").tag(Decimal(minute))
                                        }
                                    }
                                    .pickerStyle(WheelPickerStyle())
                                    .frame(maxWidth: .infinity)

                                    Picker(
                                        selection: Binding(
                                            get: { uamMinutes ?? state.defaultUamMinutes },
                                            set: {
                                                uamMinutes = $0
                                                hasChanges = true
                                            }
                                        ),
                                        label: Text("")
                                    ) {
                                        ForEach(Array(stride(from: 0, through: 180, by: 5)), id: \.self) { minute in
                                            Text("\(minute) min").tag(Decimal(minute))
                                        }
                                    }
                                    .pickerStyle(WheelPickerStyle())
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listRowBackground(Color.chart)
    }

    private var saveButton: some View {
        let (isInvalid, errorMessage) = isOverrideInvalid()

        return Section(
            header:
            HStack {
                Spacer()
                Text(errorMessage ?? "").textCase(nil)
                    .foregroundColor(colorScheme == .dark ? .orange : .accentColor)
                Spacer()
            },
            content: {
                Button(action: {
                    saveChanges()

                    do {
                        guard let moc = override.managedObjectContext else { return }
                        guard moc.hasChanges else { return }
                        try moc.save()

                        if let currentActiveOverride = state.currentActiveOverride {
                            Task {
                                await state.disableAllActiveOverrides(
                                    except: currentActiveOverride.objectID,
                                    createOverrideRunEntry: false
                                )
                                // Update View
                                state.updateLatestOverrideConfiguration()
                            }
                        }

                        hasChanges = false
                        presentationMode.wrappedValue.dismiss()
                    } catch {
                        debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to edit Override")
                    }
                }, label: {
                    Text("Save Override")
                })
                    .disabled(isInvalid) // Disable button if changes are invalid
                    .frame(maxWidth: .infinity, alignment: .center)
                    .tint(.white)
            }
        )
        .listRowBackground(isInvalid ? Color(.systemGray4) : Color(.systemBlue))
    }

    private func isOverrideInvalid() -> (Bool, String?) {
        let noDurationSpecified = !indefinite && duration == 0
        let targetZeroWithOverride = target_override && (target ?? 0 < 72 || target ?? 0 > 270)
        let allSettingsDefault = percentage == 100 && !target_override && !advancedSettings &&
            !smbIsOff && !smbIsScheduledOff

        if noDurationSpecified {
            return (true, "Enable indefinitely or set a duration.")
        }

        if targetZeroWithOverride {
            return (true, "Target glucose is out of range (\(state.units == .mgdL ? "72-270" : "4-14")).")
        }

        if allSettingsDefault {
            return (true, "All settings are at default values.")
        }

        if !hasChanges {
            return (true, nil)
        }

        return (false, nil)
    }

    private func saveChanges() {
        if !override.isPreset, hasChanges, name == (override.name ?? "") {
            override.name = "Custom Override"
        } else {
            override.name = name
        }
        override.percentage = percentage
        override.indefinite = indefinite
        override.duration = NSDecimalNumber(decimal: duration)
        override.target = NSDecimalNumber(decimal: target ?? 100)
        override.advancedSettings = advancedSettings
        override.smbIsOff = smbIsOff
        override.smbIsScheduledOff = smbIsScheduledOff
        override.start = start.map { NSDecimalNumber(decimal: $0) }
        override.end = end.map { NSDecimalNumber(decimal: $0) }
        override.isfAndCr = isfAndCr
        override.isf = isf
        override.cr = cr
        override.smbMinutes = smbMinutes.map { NSDecimalNumber(decimal: $0) }
        override.uamMinutes = uamMinutes.map { NSDecimalNumber(decimal: $0) }
        override.isUploadedToNS = false
    }

    private func resetValues() {
        name = override.name ?? ""
        percentage = override.percentage
        indefinite = override.indefinite
        duration = override.duration?.decimalValue ?? 0
        target = override.target?.decimalValue
        advancedSettings = override.advancedSettings
        smbIsOff = override.smbIsOff
        smbIsScheduledOff = override.smbIsScheduledOff
        start = override.start?.decimalValue
        end = override.end?.decimalValue
        isfAndCr = override.isfAndCr
        isf = override.isf
        cr = override.cr
        smbMinutes = override.smbMinutes?.decimalValue ?? state.defaultSmbMinutes
        uamMinutes = override.uamMinutes?.decimalValue ?? state.defaultUamMinutes
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

struct TargetPicker: View {
    let label: String
    @Binding var selection: Decimal
    let options: [Decimal]
    let units: GlucoseUnits
    @Binding var hasChanges: Bool
    @Binding var targetStep: Decimal
    @State private var isDisplayed: Bool = false

    var body: some View {
        VStack {
            HStack {
                Text(label)
                Spacer()
                Text(
                    (units == .mgdL ? selection.description : selection.formattedAsMmolL) + " " + units.rawValue
                )
                .foregroundColor(!isDisplayed ? .primary : .accentColor)
            }
            .onTapGesture {
                isDisplayed.toggle()
            }
            if isDisplayed {
                HStack {
                    // Radio buttons and text on the left side
                    VStack(alignment: .leading) {
                        // Radio buttons for step iteration
                        let stepChoices: [Decimal] = units == .mgdL ? [1, 5] : [1, 9]
                        ForEach(stepChoices, id: \.self) { step in
                            let label = (units == .mgdL ? step.description : step.formattedAsMmolL) + " " +
                                units.rawValue
                            RadioButton(
                                isSelected: targetStep == step,
                                label: label
                            ) {
                                targetStep = step
                                selection = OverrideConfig.StateModel.roundTargetToStep(selection, step)
                            }
                            .padding(.top, 10)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Spacer()

                    // Picker on the right side
                    Picker(selection: Binding(
                        get: { OverrideConfig.StateModel.roundTargetToStep(selection, targetStep) },
                        set: {
                            selection = $0
                            hasChanges = true
                        }
                    ), label: Text("")) {
                        ForEach(options, id: \.self) { option in
                            Text((units == .mgdL ? option.description : option.formattedAsMmolL) + " " + units.rawValue)
                                .tag(option)
                        }
                    }
                    .pickerStyle(WheelPickerStyle())
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
