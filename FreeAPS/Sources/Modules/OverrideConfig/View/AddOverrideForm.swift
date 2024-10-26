import Foundation
import SwiftUI

struct AddOverrideForm: View {
    @Environment(\.presentationMode) var presentationMode
    @Bindable var state: OverrideConfig.StateModel
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
    @Environment(\.colorScheme) var colorScheme

    @Environment(\.dismiss) var dismiss

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
                addOverride()
                saveButton
            }
            .listSectionSpacing(10)
            .padding(.top, 30)
            .ignoresSafeArea(edges: .top)
            .scrollContentBackground(.hidden).background(color)
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
                NavigationStack {
                    List {
                        Text("Lorem Ipsum Dolor Sit Amet")
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

            Section {
                Toggle(isOn: $state.indefinite) {
                    Text("Enable Indefinitely")
                }

                if !state.indefinite {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(formatHrMin(Int(state.overrideDuration)))
                            .foregroundColor(!displayPickerDuration ? .primary : .accentColor)
                    }
                    .onTapGesture {
                        displayPickerDuration = toggleScrollWheel(displayPickerDuration)
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
                                state.overrideDuration = convertToMinutes(durationHours, durationMinutes)
                            }

                            Picker("Minutes", selection: $durationMinutes) {
                                ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { minute in
                                    Text("\(minute) min").tag(minute)
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)
                            .onChange(of: durationMinutes) {
                                state.overrideDuration = convertToMinutes(durationHours, durationMinutes)
                            }
                        }
                        .listRowSeparator(.hidden, edges: .top)
                    }
                }
            }
            .listRowBackground(Color.chart)

            Section(footer: percentageDescription(state.overridePercentage)) {
                // Percentage Picker
                HStack {
                    Text("Change Basal Rate by")
                    Spacer()
                    Text("\(state.overridePercentage.formatted(.number)) %")
                        .foregroundColor(!displayPickerPercentage ? .primary : .accentColor)
                }
                .onTapGesture {
                    displayPickerPercentage = toggleScrollWheel(displayPickerPercentage)
                }

                if displayPickerPercentage {
                    HStack {
                        // Radio buttons and text on the left side
                        VStack(alignment: .leading) {
                            // Radio buttons for step iteration
                            ForEach([1, 5], id: \.self) { step in
                                RadioButton(isSelected: percentageStep == step, label: "\(step) %") {
                                    percentageStep = step
                                    state.overridePercentage = OverrideConfig.StateModel.roundOverridePercentageToStep(
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
                        Text(option.rawValue).tag(option)
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
                    Text("Override Profile Target")
                }

                if state.shouldOverrideTarget {
                    HStack {
                        Text("Target Glucose")
                        Spacer()
                        Text(
                            (state.units == .mgdL ? state.target.description : state.target.formattedAsMmolL) + " " + state
                                .units.rawValue
                        )
                        .foregroundColor(!displayPickerTarget ? .primary : .accentColor)
                    }
                    .onTapGesture {
                        displayPickerTarget = toggleScrollWheel(displayPickerTarget)
                    }

                    if displayPickerTarget {
                        HStack {
                            // Radio buttons and text on the left side
                            VStack(alignment: .leading) {
                                // Radio buttons for step iteration
                                let stepChoices: [Decimal] = state.units == .mgdL ? [1, 5] : [1, 9]
                                ForEach(stepChoices, id: \.self) { step in
                                    let label = (state.units == .mgdL ? step.description : step.formattedAsMmolL) + " " +
                                        state.units.rawValue

                                    RadioButton(
                                        isSelected: targetStep == step,
                                        label: label
                                    ) {
                                        targetStep = step
                                        state.target = OverrideConfig.StateModel.roundTargetToStep(state.target, targetStep)
                                    }
                                    .padding(.top, 10)
                                }
                            }
                            .frame(maxWidth: .infinity)

                            Spacer()

                            // Picker on the right side
                            let settingsProvider = PickerSettingsProvider.shared
                            let glucoseSetting = PickerSetting(value: 0, step: targetStep, min: 72, max: 270, type: .glucose)
                            Picker(selection: Binding(
                                get: { OverrideConfig.StateModel.roundTargetToStep(state.target, targetStep) },
                                set: { state.target = $0 }
                            ), label: Text("")) {
                                ForEach(
                                    settingsProvider.generatePickerValues(
                                        from: glucoseSetting,
                                        units: state.units,
                                        roundMinToStep: true
                                    ),
                                    id: \.self
                                ) { glucose in
                                    Text(
                                        (state.units == .mgdL ? glucose.description : glucose.formattedAsMmolL) + " " + state
                                            .units.rawValue
                                    )
                                    .tag(glucose)
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

            Section {
                // Picker for ISF/CR settings
                Picker("Disable SMBs", selection: $selectedDisableSmbOption) {
                    ForEach(DisableSmbOptions.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
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
                            is24HourFormat() ? format24Hour(Int(truncating: state.start as NSNumber)) + ":00" :
                                convertTo12HourFormat(Int(truncating: state.start as NSNumber))
                        )
                        .foregroundColor(!displayPickerDisableSmbSchedule ? .primary : .accentColor)
                        Spacer()
                        Divider().frame(width: 1, height: 20)
                        Spacer()
                        Text("To")
                        Spacer()
                        Text(
                            is24HourFormat() ? format24Hour(Int(truncating: state.end as NSNumber)) + ":00" :
                                convertTo12HourFormat(Int(truncating: state.end as NSNumber))
                        )
                        .foregroundColor(!displayPickerDisableSmbSchedule ? .primary : .accentColor)
                        Spacer()
                    }
                    .onTapGesture {
                        displayPickerDisableSmbSchedule = toggleScrollWheel(displayPickerDisableSmbSchedule)
                    }

                    if displayPickerDisableSmbSchedule {
                        HStack {
                            // From Picker
                            Picker(selection: Binding(
                                get: { Int(truncating: state.start as NSNumber) },
                                set: { state.start = Decimal($0) }
                            ), label: Text("")) {
                                ForEach(0 ..< 24, id: \.self) { hour in
                                    Text(is24HourFormat() ? format24Hour(hour) + ":00" : convertTo12HourFormat(hour))
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
                                    Text(is24HourFormat() ? format24Hour(hour) + ":00" : convertTo12HourFormat(hour))
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
                            Spacer()
                            Divider().frame(width: 1, height: 20)
                            Spacer()
                            Text("UAM")
                            Spacer()
                            Text("\(state.uamMinutes.formatted(.number)) min")
                                .foregroundColor(!displayPickerSmbMinutes ? .primary : .accentColor)
                        }
                        .onTapGesture {
                            displayPickerSmbMinutes = toggleScrollWheel(displayPickerSmbMinutes)
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
                            state.isEnabled.toggle()
                            await state.saveCustomOverride()
                            await state.resetStateVariables()
                            dismiss()
                        }
                    }, label: {
                        Text("Enact Override")
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
            return (true, "Enable indefinitely or set a duration.")
        }

        if targetZeroWithOverride {
            return (true, "Target glucose is out of range (\(state.units == .mgdL ? "72-270" : "4-14")).")
        }

        if allSettingsDefault {
            return (true, "All settings are at default values.")
        }

        return (false, nil)
    }
}
