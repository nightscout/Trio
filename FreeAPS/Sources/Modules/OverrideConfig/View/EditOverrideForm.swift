import Foundation
import SwiftUI

struct EditOverrideForm: View {
    @ObservedObject var override: OverrideStored
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @StateObject var state: OverrideConfig.StateModel

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
    @State private var displayPickerTarget: Bool = false
    @State private var displayPickerDisableSmbSchedule: Bool = false
    @State private var displayPickerSmbMinutes: Bool = false

    init(overrideToEdit: OverrideStored, state: OverrideConfig.StateModel) {
        override = overrideToEdit
        _state = StateObject(wrappedValue: state)
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
            }
            .onDisappear {
                if !hasChanges {
                    // Reset UI changes
                    resetValues()
                }
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
                                    roundPercentageToStep()
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
                    let step: Decimal = state.units == .mgdL ? 1 : 2
                    ScrollWheelPicker(
                        label: "Target Glucose",
                        selection: Binding(
                            get: { target ?? Decimal(100) },
                            set: { target = $0 }
                        ),
                        options: Array(stride(from: Decimal(72), through: Decimal(270), by: step)),
                        formatter: { formattedGlucose(glucose: $0) },
                        hasChanges: $hasChanges
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

    private func formattedGlucose(glucose: Decimal) -> String {
        let formattedValue: String
        if state.units == .mgdL {
            formattedValue = glucoseFormatter.string(from: glucose as NSDecimalNumber) ?? "\(glucose)"
        } else {
            formattedValue = glucose.formattedAsMmolL
        }
        return "\(formattedValue) \(state.units.rawValue)"
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
        if target_override {
            override.target = target.map {
                state.units == .mmolL ? NSDecimalNumber(decimal: $0.asMgdL) : NSDecimalNumber(decimal: $0)
            }
        } else {
            override.target = 0
        }
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

    private func roundPercentageToStep() {
        // Check if overridePercentage is not divisible by the selected step
        if percentage.truncatingRemainder(dividingBy: Double(percentageStep)) != 0 {
            let roundedValue: Double

            if percentage > 100 {
                // Round down to the nearest valid step away from 100
                let stepCount = (percentage - 100) / Double(percentageStep)
                roundedValue = 100 + floor(stepCount) * Double(percentageStep)
            } else {
                // Round up to the nearest valid step away from 100
                let stepCount = (100 - percentage) / Double(percentageStep)
                roundedValue = 100 - floor(stepCount) * Double(percentageStep)
            }

            // Ensure the value stays between 10 and 200
            percentage = max(10, min(roundedValue, 200))
        }
    }
}

struct ScrollWheelPicker<T: Hashable>: View {
    let label: String
    @Binding var selection: T
    let options: [T]
    let formatter: (T) -> String
    @Binding var hasChanges: Bool
    @State private var isDisplayed: Bool = false

    var body: some View {
        VStack {
            HStack {
                Text(label)
                Spacer()
                Text(formatter(selection))
                    .foregroundColor(!isDisplayed ? .primary : .accentColor)
            }
            .onTapGesture {
                isDisplayed.toggle()
            }
            if isDisplayed {
                Picker(selection: Binding(
                    get: { selection },
                    set: {
                        selection = $0
                        hasChanges = true
                    }
                ), label: Text("")) {
                    ForEach(options, id: \.self) { option in
                        Text(formatter(option)).tag(option)
                    }
                }
                .pickerStyle(WheelPickerStyle())
                .frame(maxWidth: .infinity)
            }
        }
    }
}
