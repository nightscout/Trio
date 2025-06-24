import Foundation
import SwiftUI

struct AddOverrideForm: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @Environment(AppState.self) var appState
    @Bindable var state: Adjustments.StateModel
    @State private var selectedIsfCrOption: IsfAndOrCrOptions = .isfAndCr
    @State private var selectedDisableSmbOption: DisableSmbOptions = .dontDisable
    @State private var percentageStep: Int = 5
    @State private var displayPickerPercentage: Bool = false
    @State private var displayPickerDuration: Bool = false
    @State private var targetStep: Decimal = 5
    @State private var displayPickerTarget: Bool = false
    @State private var displayPickerDisableSmbSchedule: Bool = false
    @State private var displayPickerSmbMinutes: Bool = false
    @State private var durationHours = 0
    @State private var durationMinutes = 0
    @State private var overrideTarget = false
    @State private var didPressSave = false

    var body: some View {
        NavigationView {
            List {
                addOverride()
                saveButton
            }
            .listSectionSpacing(10)
            .padding(.top, 30)
            .ignoresSafeArea(edges: .top)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Add Override")
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
            .sheet(isPresented: $state.isHelpSheetPresented) {
                OverrideHelpView(state: state, helpSheetDetent: $state.helpSheetDetent)
            }
        }
    }

    @ViewBuilder private func addOverride() -> some View {
        Group {
            Section {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("(Optional)", text: $state.overrideName).multilineTextAlignment(.trailing)
                }
            }
            .listRowBackground(Color.chart)

            Section(footer: state.percentageDescription(state.overridePercentage)) {
                // Percentage Picker
                HStack {
                    Text("Basal Rate Adjustment")
                    Spacer()
                    Text("\(state.overridePercentage.formatted(.number)) %")
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
                                    state.overridePercentage = Adjustments.StateModel.roundOverridePercentageToStep(
                                        state.overridePercentage,
                                        step
                                    )
                                }
                                .padding(.top, 10)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Spacer()

                        // Picker on the right side
                        Picker(
                            selection: Binding(
                                get: { Int(truncating: state.overridePercentage as NSNumber) },
                                set: { state.overridePercentage = Double($0) }
                            ), label: Text("")
                        ) {
                            ForEach(Array(stride(from: 40, through: 150, by: percentageStep)), id: \.self) { percent in
                                Text("\(percent) %").tag(percent)
                            }
                        }
                        .pickerStyle(WheelPickerStyle())
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden, edges: .top)
                }

                // Picker for ISF/CR settings
                Picker("Also Inversely Change", selection: $selectedIsfCrOption) {
                    ForEach(IsfAndOrCrOptions.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: selectedIsfCrOption) { _, newValue in
                    switch newValue {
                    case .isfAndCr:
                        state.isfAndCr = true
                        state.isf = true
                        state.cr = true
                    case .isf:
                        state.isfAndCr = false
                        state.isf = true
                        state.cr = false
                    case .cr:
                        state.isfAndCr = false
                        state.isf = false
                        state.cr = true
                    case .nothing:
                        state.isfAndCr = false
                        state.isf = false
                        state.cr = false
                    }
                }
            }
            .listRowBackground(Color.chart)

            Section {
                Toggle(isOn: $state.shouldOverrideTarget) {
                    Text("Override Target")
                }

                if state.shouldOverrideTarget {
                    let settingsProvider = PickerSettingsProvider.shared
                    let glucoseSetting = PickerSetting(value: 0, step: targetStep, min: 72, max: 270, type: .glucose)
                    TargetPicker(
                        label: "Target Glucose",
                        selection: Binding(
                            get: { state.target },
                            set: { state.target = $0 }
                        ),
                        options: settingsProvider.generatePickerValues(
                            from: glucoseSetting,
                            units: state.units,
                            roundMinToStep: true
                        ),
                        units: state.units,
                        targetStep: $targetStep,
                        displayPickerTarget: $displayPickerTarget,
                        toggleScrollWheel: toggleScrollWheel
                    )
                    .onAppear {
                        if state.target == 0 {
                            state.target = 100
                        }
                    }
                }
            }
            .listRowBackground(Color.chart)

            Section {
                // Picker for ISF/CR settings
                Picker("Disable SMBs", selection: $selectedDisableSmbOption) {
                    ForEach(DisableSmbOptions.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: selectedDisableSmbOption) { _, newValue in
                    switch newValue {
                    case .dontDisable:
                        state.smbIsOff = false
                        state.smbIsScheduledOff = false
                    case .disable:
                        state.smbIsOff = true
                        state.smbIsScheduledOff = false
                    case .disableOnSchedule:
                        state.smbIsOff = false
                        state.smbIsScheduledOff = true
                    }
                }

                if state.smbIsScheduledOff {
                    // First Hour SMBs Are Disabled
                    HStack {
                        Text("From")
                        Spacer()
                        Text(
                            state.is24HourFormat() ? state.format24Hour(Int(truncating: state.start as NSNumber)) + ":00" :
                                state.convertTo12HourFormat(Int(truncating: state.start as NSNumber))
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
                            state.is24HourFormat() ? state.format24Hour(Int(truncating: state.end as NSNumber)) + ":00" :
                                state.convertTo12HourFormat(Int(truncating: state.end as NSNumber))
                        )
                        .foregroundColor(!displayPickerDisableSmbSchedule ? .primary : .accentColor)
                        .onTapGesture {
                            displayPickerDisableSmbSchedule = toggleScrollWheel(displayPickerDisableSmbSchedule)
                        }
                        Spacer()
                    }

                    if displayPickerDisableSmbSchedule {
                        HStack {
                            // From Picker
                            Picker(selection: Binding(
                                get: { Int(truncating: state.start as NSNumber) },
                                set: { state.start = Decimal($0) }
                            ), label: Text("")) {
                                ForEach(0 ..< 24, id: \.self) { hour in
                                    Text(
                                        state.is24HourFormat() ? state.format24Hour(hour) + ":00" : state
                                            .convertTo12HourFormat(hour)
                                    )
                                    .tag(hour)
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)

                            // To Picker
                            Picker(selection: Binding(
                                get: { Int(truncating: state.end as NSNumber) },
                                set: { state.end = Decimal($0) }
                            ), label: Text("")) {
                                ForEach(0 ..< 24, id: \.self) { hour in
                                    Text(
                                        state.is24HourFormat() ? state.format24Hour(hour) + ":00" : state
                                            .convertTo12HourFormat(hour)
                                    )
                                    .tag(hour)
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

            if !state.smbIsOff {
                Section {
                    Toggle(isOn: $state.advancedSettings) {
                        Text("Override Max SMB Minutes")
                    }

                    if state.advancedSettings {
                        // SMB Minutes Picker
                        HStack {
                            Text("SMB")
                            Spacer()
                            Text("\(state.smbMinutes.formatted(.number)) min")
                                .foregroundColor(!displayPickerSmbMinutes ? .primary : .accentColor)
                                .onTapGesture {
                                    displayPickerSmbMinutes = toggleScrollWheel(displayPickerSmbMinutes)
                                }
                            Spacer()
                            Divider().frame(width: 1, height: 20)
                            Spacer()
                            Text("UAM")
                            Spacer()
                            Text("\(state.uamMinutes.formatted(.number)) min")
                                .foregroundColor(!displayPickerSmbMinutes ? .primary : .accentColor)
                                .onTapGesture {
                                    displayPickerSmbMinutes = toggleScrollWheel(displayPickerSmbMinutes)
                                }
                        }

                        if displayPickerSmbMinutes {
                            HStack {
                                Picker(selection: Binding(
                                    get: { Int(truncating: state.smbMinutes as NSNumber) },
                                    set: { state.smbMinutes = Decimal($0) }
                                ), label: Text("")) {
                                    ForEach(Array(stride(from: 0, through: 180, by: 5)), id: \.self) { minute in
                                        Text("\(minute) min").tag(minute)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(maxWidth: .infinity)

                                Picker(selection: Binding(
                                    get: { Int(truncating: state.uamMinutes as NSNumber) },
                                    set: { state.uamMinutes = Decimal($0) }
                                ), label: Text("")) {
                                    ForEach(Array(stride(from: 0, through: 180, by: 5)), id: \.self) { minute in
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

            Section {
                Toggle(isOn: $state.indefinite) {
                    Text("Enable Indefinitely")
                }

                if !state.indefinite {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(state.formatHoursAndMinutes(Int(state.overrideDuration)))
                            .foregroundColor(!displayPickerDuration ? .primary : .accentColor)
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
                                state.overrideDuration = state.convertToMinutes(durationHours, durationMinutes)
                            }

                            Picker("Minutes", selection: $durationMinutes) {
                                ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { minute in
                                    Text("\(minute) min").tag(minute)
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)
                            .onChange(of: durationMinutes) {
                                state.overrideDuration = state.convertToMinutes(durationHours, durationMinutes)
                            }
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
                            if state.indefinite { state.overrideDuration = 0 }
                            state.isOverrideEnabled.toggle()
                            await state.saveCustomOverride()
                            await state.resetStateVariables()
                            dismiss()
                        }
                    }, label: {
                        Text("Start Override")
                    })
                        .disabled(isInvalid)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .tint(.white)
                }
            ).listRowBackground(isInvalid ? Color(.systemGray4) : Color(.systemBlue))

            Section {
                Button(action: {
                    Task {
                        await state.saveOverridePreset()
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

    private func toggleScrollWheel(_ toggle: Bool) -> Bool {
        displayPickerDuration = false
        displayPickerPercentage = false
        displayPickerTarget = false
        displayPickerDisableSmbSchedule = false
        displayPickerSmbMinutes = false
        return !toggle
    }

    private func isOverrideInvalid() -> (Bool, String?) {
        let noDurationSpecified = !state.indefinite && state.overrideDuration == 0
        let targetZeroWithOverride = state.shouldOverrideTarget && state.target == 0
        let allSettingsDefault = state.overridePercentage == 100 && !state.shouldOverrideTarget &&
            !state.advancedSettings && !state.smbIsOff && !state.smbIsScheduledOff

        if noDurationSpecified {
            return (true, String(localized: "Enable indefinitely or set a duration."))
        }

        if targetZeroWithOverride {
            return (true, String(localized: "Target glucose is out of range (\(state.units == .mgdL ? "72-270" : "4-14"))."))
        }

        if allSettingsDefault {
            return (true, String(localized: "All settings are at default values."))
        }

        return (false, nil)
    }
}
