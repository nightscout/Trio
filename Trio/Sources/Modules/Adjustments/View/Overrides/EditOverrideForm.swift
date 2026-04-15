import Foundation
import SwiftUI

struct EditOverrideForm: View {
    var override: OverrideStored
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState
    @Bindable var state: Adjustments.StateModel

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
    @State private var percentageStep: Int = 1
    @State private var displayPickerPercentage: Bool = false
    @State private var displayPickerDuration: Bool = false
    @State private var targetStep: Decimal = 1
    @State private var displayPickerTarget: Bool = false
    @State private var displayPickerDisableSmbSchedule: Bool = false
    @State private var displayPickerSmbMinutes: Bool = false

    init(overrideToEdit: OverrideStored, state: Adjustments.StateModel) {
        override = overrideToEdit
        _state = Bindable(wrappedValue: state)
        _name = State(initialValue: overrideToEdit.name ?? "")
        _percentage = State(initialValue: overrideToEdit.percentage)
        _indefinite = State(initialValue: overrideToEdit.indefinite)
        _duration = State(initialValue: overrideToEdit.duration?.decimalValue ?? 0)
        _target = State(initialValue: overrideToEdit.target?.decimalValue)
        _target_override = State(initialValue: overrideToEdit.target != nil && overrideToEdit.target?.decimalValue != 0)
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
            .padding(.top, 30)
            .ignoresSafeArea(edges: .top)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
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
            .onDisappear {
                if !hasChanges {
                    // Reset UI changes
                    resetValues()
                }
            }
            .sheet(isPresented: $state.isHelpSheetPresented) {
                OverrideHelpView(state: state, helpSheetDetent: $state.helpSheetDetent)
            }
        }
    }

    @ViewBuilder private func editOverride() -> some View {
        Group {
            if override.name != nil {
                Section {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Name", text: $name)
                            .onChange(of: name) { hasChanges = true }
                            .multilineTextAlignment(.trailing)
                    }
                }
                .listRowBackground(Color.chart)
            }

            // Percentage Picker
            Section(footer: state.percentageDescription(percentage)) {
                HStack {
                    Text("Basal Rate Adjustment")
                    Spacer()
                    Text("\(percentage.formatted(.number)) %")
                        .foregroundColor(!displayPickerPercentage ? .primary : .accentColor)
                        .onTapGesture {
                            displayPickerPercentage = toggleScrollWheel(displayPickerPercentage)
                        }
                }

                if displayPickerPercentage {
                    HStack {
                        // Radio buttons and text on the left side
                        VStack(alignment: .leading) {
                            // Radio buttons for step iteration
                            ForEach([1, 5], id: \.self) { step in
                                RadioButton(isSelected: percentageStep == step, label: "\(step) %") {
                                    percentageStep = step
                                    percentage = Adjustments.StateModel.roundOverridePercentageToStep(percentage, step)
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
                    .listRowSeparator(.hidden, edges: .top)
                }

                // Picker for ISF/CR settings
                Picker("Also Change", selection: $selectedIsfCrOption) {
                    ForEach(IsfAndOrCrOptions.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
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
            .listRowBackground(Color.chart)

            Section {
                Toggle(isOn: $target_override) {
                    Text("Override Target")
                }
                .onChange(of: target_override) {
                    hasChanges = true
                }
                // Target Glucose Picker
                if target_override {
                    let settingsProvider = PickerSettingsProvider.shared
                    let glucoseSetting = PickerSetting(value: 0, step: targetStep, min: 72, max: 270, type: .glucose)

                    TargetPicker(
                        label: "Target Glucose",
                        selection: Binding(
                            get: { target ?? 100 },
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
                    .onAppear {
                        if target == 0 || target == nil {
                            target = 100
                        }
                    }
                }
            }
            .listRowBackground(Color.chart)

            Section {
                // Picker for Disable SMB settings
                Picker("Disable SMBs", selection: $selectedDisableSmbOption) {
                    ForEach(DisableSmbOptions.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
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
                            state.is24HourFormat() ? state.format24Hour(Int(truncating: start! as NSNumber)) + ":00" :
                                state.convertTo12HourFormat(Int(truncating: start! as NSNumber))
                        )
                        .foregroundColor(!displayPickerDisableSmbSchedule ? .primary : .accentColor)
                        .onTapGesture {
                            displayPickerDisableSmbSchedule = toggleScrollWheel(displayPickerDisableSmbSchedule)
                        }

                        Spacer()

                        Divider().frame(width: 1, height: 20)

                        Spacer()

                        Text("To")
                        Spacer()
                        Text(
                            state.is24HourFormat() ? state.format24Hour(Int(truncating: end! as NSNumber)) + ":00" :
                                state.convertTo12HourFormat(Int(truncating: end! as NSNumber))
                        )
                        .foregroundColor(!displayPickerDisableSmbSchedule ? .primary : .accentColor)
                        .onTapGesture {
                            displayPickerDisableSmbSchedule = toggleScrollWheel(displayPickerDisableSmbSchedule)
                        }
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
                                if state.is24HourFormat() {
                                    ForEach(0 ..< 24, id: \.self) { hour in
                                        Text(state.format24Hour(hour) + ":00").tag(hour)
                                    }
                                } else {
                                    ForEach(0 ..< 24, id: \.self) { hour in
                                        Text(state.convertTo12HourFormat(hour)).tag(hour)
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
                                if state.is24HourFormat() {
                                    ForEach(0 ..< 24, id: \.self) { hour in
                                        Text(state.format24Hour(hour) + ":00").tag(hour)
                                    }
                                } else {
                                    ForEach(0 ..< 24, id: \.self) { hour in
                                        Text(state.convertTo12HourFormat(hour)).tag(hour)
                                    }
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)
                        }
                        .listRowSeparator(.hidden, edges: .top)
                    }
                }
            }
            .listRowBackground(Color.chart)

            if !smbIsOff {
                Section {
                    Toggle(isOn: $advancedSettings) {
                        Text("Change Max SMB Minutes")
                    }
                    .onChange(of: advancedSettings) { hasChanges = true }

                    if advancedSettings {
                        // SMB Minutes Picker
                        HStack {
                            Text("SMB")
                            Spacer()
                            Text("\(smbMinutes?.formatted(.number) ?? "\(state.defaultSmbMinutes)") min")
                                .foregroundColor(!displayPickerSmbMinutes ? .primary : .accentColor)
                                .onTapGesture {
                                    displayPickerSmbMinutes = toggleScrollWheel(displayPickerSmbMinutes)
                                }

                            Spacer()

                            Divider().frame(width: 1, height: 20)

                            Spacer()

                            Text("UAM")
                            Spacer()
                            Text("\(uamMinutes?.formatted(.number) ?? "\(state.defaultUamMinutes)") min")
                                .foregroundColor(!displayPickerSmbMinutes ? .primary : .accentColor)
                                .onTapGesture {
                                    displayPickerSmbMinutes = toggleScrollWheel(displayPickerSmbMinutes)
                                }
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
                            .listRowSeparator(.hidden, edges: .top)
                        }
                    }
                }
                .listRowBackground(Color.chart)
            }

            Section {
                Toggle(isOn: $indefinite) { Text("Enable Indefinitely") }
                    .onChange(of: indefinite) { hasChanges = true }

                if !indefinite {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(state.formatHoursAndMinutes(Int(truncating: duration as NSNumber)))
                            .foregroundColor(!displayPickerDuration ? .primary : .accentColor)
                            .onTapGesture {
                                displayPickerDuration = toggleScrollWheel(displayPickerDuration)
                            }
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
                        .listRowSeparator(.hidden, edges: .top)
                    }
                }
            }
            .listRowBackground(Color.chart)
        }
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

                    Task {
                        do {
                            guard let moc = override.managedObjectContext else { return }
                            guard moc.hasChanges else { return }
                            try moc.save()

                            try await state.nightscoutManager.uploadProfiles()

                            // Disable previous active Override
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
            return (true, String(localized: "Enable indefinitely or set a duration."))
        }

        if targetZeroWithOverride {
            return (true, String(localized: "Target glucose is out of range (\(state.units == .mgdL ? "72-270" : "4-14"))."))
        }

        if allSettingsDefault {
            return (true, String(localized: "All settings are at default values."))
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
        override.target = target_override ? NSDecimalNumber(decimal: target ?? 100) : nil
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

    private func toggleScrollWheel(_ toggle: Bool) -> Bool {
        displayPickerDuration = false
        displayPickerPercentage = false
        displayPickerTarget = false
        displayPickerDisableSmbSchedule = false
        displayPickerSmbMinutes = false
        return !toggle
    }
}
