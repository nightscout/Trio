import Foundation
import SwiftUI

struct AddOverrideForm: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject var state: OverrideConfig.StateModel
    @State private var selectedIsfCrOption: isfAndOrCrOptions = .isfAndCr
    @State private var selectedDisableSmbOption: disableSmbOptions = .dontDisable
    @State private var displayPickerPercentage: Bool = false
    @State private var displayPickerDuration: Bool = false
    @State private var displayPickerTarget: Bool = false
    @State private var displayPickerDisableSmbSchedule: Bool = false
    @State private var displayPickerSmbMinutes: Bool = false
    @State private var durationHours = 0
    @State private var durationMinutes = 0
    @State private var overrideTarget = false
    @State private var didPressSave = false
    @Environment(\.colorScheme) var colorScheme

    @Environment(\.dismiss) var dismiss

    enum isfAndOrCrOptions: String, CaseIterable {
        case isfAndCr = "ISF/CR"
        case isf = "ISF"
        case cr = "CR"
        case none = "None"
    }

    enum disableSmbOptions: String, CaseIterable {
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

    var body: some View {
        NavigationView {
            List {
                addOverride()
                saveButton
            }
            .listSectionSpacing(20)
            .listRowSpacing(10)
            .scrollContentBackground(.hidden).background(color)
            .navigationTitle("New Override")
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }

    @ViewBuilder private func addOverride() -> some View {
        Section {
            let pad: CGFloat = 3
            VStack {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("(Optional)", text: $state.overrideName).multilineTextAlignment(.trailing)
                }
                .padding(.vertical, pad)
            }

            VStack {
                Toggle(isOn: $state.indefinite) {
                    Text("Enable Indefinitely")
                }
                .padding(.vertical, pad)
                if !state.indefinite {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(formatHrMin(Int(state.overrideDuration)))
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
                                state.overrideDuration = Decimal(totalDurationInMinutes())
                            }

                            Picker("Minutes", selection: $durationMinutes) {
                                ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { minute in
                                    Text("\(minute) min").tag(minute)
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)
                            .onChange(of: durationMinutes) {
                                state.overrideDuration = Decimal(totalDurationInMinutes())
                            }
                        }
                    }
                }
            }

            VStack {
                // Percentage Picker
                HStack {
                    Text("Change Basal Rate by")
                    Spacer()
                    Text("\(state.overridePercentage.formatted(.number)) %")
                        .foregroundColor(!displayPickerPercentage ? .primary : .accentColor)
                }
                .padding(.vertical, pad)
                .onTapGesture {
                    displayPickerPercentage.toggle()
                }

                if displayPickerPercentage {
                    Picker(selection: Binding(
                        get: { Int(truncating: state.overridePercentage as NSNumber) },
                        set: { state.overridePercentage = Double($0) }
                    ), label: Text("")) {
                        ForEach(Array(stride(from: 10, through: 200, by: 5)), id: \.self) { percent in
                            Text("\(percent) %").tag(percent)
                        }
                    }
                    .pickerStyle(WheelPickerStyle())
                    .frame(maxWidth: .infinity)
                }

                // Picker for ISF/CR settings
                Picker("Also Inversely Change", selection: $selectedIsfCrOption) {
                    ForEach(isfAndOrCrOptions.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .padding(.top, pad)
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
                    case .none:
                        state.isfAndCr = false
                        state.isf = false
                        state.cr = false
                    }
                }
            }

            VStack {
                Toggle(isOn: $state.shouldOverrideTarget) {
                    Text("Override Profile Target")
                }
                .padding(.vertical, pad)
                if state.shouldOverrideTarget {
                    VStack {
                        HStack {
                            Text("Target Glucose")
                            Spacer()
                            Text(formattedGlucose(glucose: state.target))
                                .foregroundColor(!displayPickerTarget ? .primary : .accentColor)
                        }
                        .padding(.vertical, pad)
                        .onTapGesture {
                            displayPickerTarget.toggle()
                        }

                        if displayPickerTarget {
                            let step = state.units == .mgdL ? 1 : 2
                            Picker(selection: Binding(
                                get: { Int(truncating: state.target as NSNumber) },
                                set: { state.target = Decimal($0)
                                }
                            ), label: Text("")) {
                                ForEach(
                                    Array(stride(from: 72, through: 270, by: step)),
                                    id: \.self
                                ) { glucose in
                                    Text(formattedGlucose(glucose: Decimal(glucose)))
                                        .tag(glucose)
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }

            VStack {
                // Picker for ISF/CR settings
                Picker("Disable SMBs", selection: $selectedDisableSmbOption) {
                    ForEach(disableSmbOptions.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .padding(.vertical, pad)
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
                    VStack {
                        HStack {
                            Text("From")
                            Spacer()
                            Text(
                                is24HourFormat() ? format24Hour(Int(truncating: state.start as NSNumber)) + ":00" :
                                    convertTo12HourFormat(Int(truncating: state.start as NSNumber))
                            )
                            .foregroundColor(!displayPickerDisableSmbSchedule ? .primary : .accentColor)

                            Divider().frame(width: 1, height: 20)
                            Text("To")
                            Spacer()
                            Text(
                                is24HourFormat() ? format24Hour(Int(truncating: state.end as NSNumber)) + ":00" :
                                    convertTo12HourFormat(Int(truncating: state.end as NSNumber))
                            )
                            .foregroundColor(!displayPickerDisableSmbSchedule ? .primary : .accentColor)
                            Spacer()
                        }
                        .padding(.vertical, pad)
                        .onTapGesture {
                            displayPickerDisableSmbSchedule.toggle()
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
                        }
                    }
                }
            }

            if !state.smbIsOff {
                VStack {
                    Toggle(isOn: $state.advancedSettings) {
                        Text("Override Max SMB Minutes")
                    }
                    .padding(.vertical, pad)

                    if state.advancedSettings {
                        // SMB Minutes Picker
                        VStack {
                            HStack {
                                Text("SMB")
                                Spacer()
                                Text("\(state.smbMinutes.formatted(.number)) min")
                                    .foregroundColor(!displayPickerSmbMinutes ? .primary : .accentColor)
                                Divider().frame(width: 1, height: 20)
                                Text("UAM")
                                Spacer()
                                Text("\(state.uamMinutes.formatted(.number)) min")
                                    .foregroundColor(!displayPickerSmbMinutes ? .primary : .accentColor)
                            }
                            .padding(.vertical, pad)
                            .onTapGesture {
                                displayPickerSmbMinutes.toggle()
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

        return Group {
            Section {
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
            }.listRowBackground(isInvalid ? Color(.systemGray4) : Color(.systemBlue))

            Section(
                footer: Text(errorMessage ?? "")
                    .foregroundColor(.red)
            ) {
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
                isInvalid ? Color(.systemGray4) : Color(.orange)
            )
        }
    }

    private func totalDurationInMinutes() -> Int {
        let durationTotal = (durationHours * 60) + durationMinutes
        return max(0, durationTotal)
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
