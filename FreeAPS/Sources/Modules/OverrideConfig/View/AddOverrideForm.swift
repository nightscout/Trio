import Foundation
import SwiftUI

struct AddOverrideForm: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject var state: OverrideConfig.StateModel
    @State private var displayPickerDuration: Bool = false
    @State private var displayPickerStart: Bool = false
    @State private var displayPickerEnd: Bool = false
    @State private var displayPickerSmbMinutes: Bool = false
    @State private var displayPickerUamMinutes: Bool = false
    @State private var durationHours = 0
    @State private var durationMinutes = 0
    @State private var overrideTarget = false
    @Environment(\.colorScheme) var colorScheme
    @State private var showAlert = false
    @State private var alertString = ""

    @Environment(\.dismiss) var dismiss

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

    private var alertMessage: String {
        let target: String = state.units == .mgdL ? "70-270 mg/dl" : "4-15 mmol/l"
        return "Please enter a valid target between" + " \(target)."
    }

    var body: some View {
        NavigationView {
            Form {
                addOverride()
            }.scrollContentBackground(.hidden).background(color)
                .navigationTitle("Add Override")
                .navigationBarItems(trailing: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                })
        }
    }

    @ViewBuilder private func addOverride() -> some View {
        Section {
            VStack {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("(Optional)", text: $state.overrideName).multilineTextAlignment(.trailing)
                }
            }

            VStack {
                HStack {
                    Spacer()

                    // Decrement button
                    Button(action: {
                        if state.overrideSliderPercentage > 10 {
                            state.overrideSliderPercentage -= 1
                        }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title)
                            .foregroundColor(state.overrideSliderPercentage > 10 ? .accentColor : .loopGray)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()

                    Text("\(Int(state.overrideSliderPercentage)) %")
                        .font(.largeTitle)
                        .foregroundColor(.accentColor)

                    Spacer()

                    // Increment button
                    Button(action: {
                        if state.overrideSliderPercentage < 200 {
                            state.overrideSliderPercentage += 1
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                            .foregroundColor(state.overrideSliderPercentage < 200 ? .accentColor : .loopGray)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()
                }
                .padding()

                // Slider to adjust value
                Slider(
                    value: $state.overrideSliderPercentage,
                    in: 10 ... 200,
                    step: 1
                )

                Toggle(isOn: $state.isfAndCr) {
                    Text("Change ISF and CR")
                }
                if !state.isfAndCr {
                    Toggle(isOn: $state.isf) {
                        Text("Change ISF")
                    }

                    Toggle(isOn: $state.cr) {
                        Text("Change CR")
                    }
                }
            }

            VStack {
                Toggle(isOn: $state.indefinite) {
                    Text("Enable Indefinitely")
                }
                if !state.indefinite {
                    VStack {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text(formatHrMin(Int(state.overrideDuration)))
                                .foregroundColor(!displayPickerDuration ? .primary : .accentColor)
                        }
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
                                .frame(width: 100)
                                .onChange(of: durationHours) { _ in
                                    state.overrideDuration = Decimal(totalDurationInMinutes())
                                }

                                Picker("Minutes", selection: $durationMinutes) {
                                    ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { minute in
                                        Text("\(minute) min").tag(minute)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(width: 100)
                                .onChange(of: durationMinutes) { _ in
                                    state.overrideDuration = Decimal(totalDurationInMinutes())
                                }
                            }
                        }
                    }
                    .padding(.top)
                }
            }

            VStack {
                Toggle(isOn: $state.shouldOverrideTarget) {
                    Text("Override Profile Target")
                }
                if state.shouldOverrideTarget {
                    HStack {
                        Text("Target Glucose")
                        TextFieldWithToolBar(text: $state.target, placeholder: "0", numberFormatter: glucoseFormatter)
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                }
            }

            Toggle(isOn: $state.advancedSettings) {
                Text("More Options")
            }
            if state.advancedSettings {
                Toggle(isOn: Binding(
                    get: { state.smbIsOff },
                    set: { newValue in
                        state.smbIsOff = newValue
                        if newValue {
                            state.smbIsScheduledOff = false
                        }
                    }
                )) {
                    Text("Disable SMBs")
                }

                VStack {
                    Toggle(isOn: Binding(
                        get: { state.smbIsScheduledOff },
                        set: { newValue in
                            state.smbIsScheduledOff = newValue
                            if newValue {
                                state.smbIsOff = false
                            }
                        }
                    )) {
                        Text("Schedule When SMBs Are Disabled")
                    }

                    if state.smbIsScheduledOff {
                        // First Hour SMBs Are Disabled
                        VStack {
                            HStack {
                                Text("From")
                                Spacer()

                                Text(
                                    is24HourFormat() ? format24Hour(Int(truncating: state.start as NSNumber)) + ":00" :
                                        convertTo12HourFormat(Int(truncating: state.start as NSNumber))
                                )
                                .foregroundColor(!displayPickerStart ? .primary : .accentColor)
                            }
                            .onTapGesture {
                                displayPickerStart.toggle()
                            }

                            if displayPickerStart {
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
                            }
                        }
                        .padding(.top, 10)

                        // First Hour SMBs Are Resumed
                        VStack {
                            HStack {
                                Text("To")
                                Spacer()
                                Text(
                                    is24HourFormat() ? format24Hour(Int(truncating: state.end as NSNumber)) + ":00" :
                                        convertTo12HourFormat(Int(truncating: state.end as NSNumber))
                                )
                                .foregroundColor(!displayPickerEnd ? .primary : .accentColor)
                            }
                            .onTapGesture {
                                displayPickerEnd.toggle()
                            }

                            if displayPickerEnd {
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
                        }
                        .padding(.vertical, 10)
                    }
                }

                if !state.smbIsOff {
                    VStack {
                        // SMB Minutes Picker
                        VStack {
                            HStack {
                                Text("Max SMB Minutes")
                                Spacer()

                                Text("\(state.smbMinutes.formatted(.number)) min")
                                    .foregroundColor(!displayPickerSmbMinutes ? .primary : .accentColor)
                            }
                            .onTapGesture {
                                displayPickerSmbMinutes.toggle()
                            }

                            if displayPickerSmbMinutes {
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
                            }
                        }
                        .padding(.top)

                        // UAM SMB Minutes Picker
                        VStack {
                            HStack {
                                Text("Max UAM SMB Minutes")
                                Spacer()
                                Text("\(state.uamMinutes.formatted(.number)) min")
                                    .foregroundColor(!displayPickerUamMinutes ? .primary : .accentColor)
                            }
                            .onTapGesture {
                                displayPickerUamMinutes.toggle()
                            }

                            if displayPickerUamMinutes {
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
                        }
                        .padding(.top)
                    }
                }
            }

            startAndSaveProfiles
        }
        header: { Text("Add custom Override") }
        footer: {
            Text(
                "Your profile ISF and CR will be inversely adjusted with the override percentage."
            )
        }.listRowBackground(Color.chart)
    }

    private var startAndSaveProfiles: some View {
        HStack {
            Button("Start New Override") {
                if !state.isInputInvalid(target: state.target) {
                    showAlert.toggle()

                    alertString = "\(state.overrideSliderPercentage.formatted(.number)) %, " +
                        (
                            state.overrideDuration > 0 || !state
                                .indefinite ?
                                (
                                    state
                                        .overrideDuration
                                        .formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) +
                                        " min."
                                ) :
                                NSLocalizedString(" infinite duration.", comment: "")
                        ) +
                        (
                            (state.target == 0 || !state.shouldOverrideTarget) ? "" :
                                (" Target: " + state.target.formatted() + " " + state.units.rawValue + ".")
                        )
                        +
                        (
                            state
                                .smbIsOff ?
                                NSLocalizedString(
                                    " SMBs are disabled either by schedule or during the entire duration.",
                                    comment: ""
                                ) : ""
                        )
                        +
                        "\n\n"
                        +
                        NSLocalizedString(
                            "Starting this override will change your profiles and/or your Target Glucose used for looping during the entire selected duration. Tapping ”Start Override” will start your new Override or edit your current active Override.",
                            comment: ""
                        )
                }
            }
            .disabled(unChanged())
            .buttonStyle(BorderlessButtonStyle())
            .font(.callout)
            .controlSize(.mini)
            .alert(
                "Start Override",
                isPresented: $showAlert,
                actions: {
                    Button("Cancel", role: .cancel) { state.isEnabled = false }
                    Button("Start Override", role: .destructive) {
                        Task {
                            if state.indefinite { state.overrideDuration = 0 }
                            state.isEnabled.toggle()
                            await state.saveCustomOverride()
                            await state.resetStateVariables()
                            dismiss()
                        }
                    }
                },
                message: {
                    Text(alertString)
                }
            )
            .alert(isPresented: $state.showInvalidTargetAlert) {
                Alert(
                    title: Text("Invalid Input"),
                    message: Text("\(state.alertMessage)"),
                    dismissButton: .default(Text("OK")) { state.showInvalidTargetAlert = false }
                )
            }
            Button {
                Task {
                    if !state.isInputInvalid(target: state.target) {
                        await state.saveOverridePreset()
                        dismiss()
                    }
                }
            }
            label: { Text("Save as Preset") }
                .tint(.orange)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .buttonStyle(BorderlessButtonStyle())
                .controlSize(.mini)
                .disabled(unChanged())
        }
    }

    private func totalDurationInMinutes() -> Int {
        let durationTotal = (durationHours * 60) + durationMinutes
        return max(0, durationTotal)
    }

    private func unChanged() -> Bool {
        let defaultProfile = state.overrideSliderPercentage == 100 && !state.shouldOverrideTarget && !state.advancedSettings
        let noDurationSpecified = !state.indefinite && state.overrideDuration == 0
        let targetZeroWithOverride = state.shouldOverrideTarget && state.target == 0
        let allSettingsDefault = state.overrideSliderPercentage == 100 && !state.shouldOverrideTarget && !state.smbIsOff && !state
            .smbIsScheduledOff && state.smbMinutes == state.defaultSmbMinutes && state.uamMinutes == state.defaultUamMinutes

        return defaultProfile || noDurationSpecified || targetZeroWithOverride || allSettingsDefault
    }
}

// Function to check if the phone is using 24-hour format
func is24HourFormat() -> Bool {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    let dateString = formatter.string(from: Date())

    return !dateString.contains("AM") && !dateString.contains("PM")
}

// Helper function to convert hours to AM/PM format
func convertTo12HourFormat(_ hour: Int) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h a"

    // Create a date from the hour and format it to AM/PM
    let calendar = Calendar.current
    let components = DateComponents(hour: hour)
    let date = calendar.date(from: components) ?? Date()

    return formatter.string(from: date)
}

// Helper function to format 24-hour numbers as two digits
func format24Hour(_ hour: Int) -> String {
    String(format: "%02d", hour)
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
