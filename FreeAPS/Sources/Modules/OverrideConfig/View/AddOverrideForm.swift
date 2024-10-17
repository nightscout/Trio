import Foundation
import SwiftUI

struct AddOverrideForm: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject var state: OverrideConfig.StateModel
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

    var body: some View {
        NavigationView {
            List {
                addOverride()
                saveButton
            }
            .listSectionSpacing(10)
            .listRowSpacing(10)
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
            }
            .onAppear { targetStep = state.units == .mgdL ? 5 : 9 }
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
                    HStack {
                        // Radio buttons and text on the left side
                        VStack(alignment: .leading) {
                            // Radio buttons for step iteration
                            ForEach([1, 5], id: \.self) { step in
                                RadioButton(isSelected: percentageStep == step, label: "\(step) %") {
                                    percentageStep = step
                                    roundOverridePercentageToStep()
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
                }

                // Picker for ISF/CR settings
                Picker("Also Inversely Change", selection: $selectedIsfCrOption) {
                    ForEach(IsfAndOrCrOptions.allCases, id: \.self) { option in
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
                    case .nothing:
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
                                            state.target = roundTargetToStep(state.target, targetStep)
                                        }
                                        .padding(.top, 10)
                                    }
                                }
                                .frame(maxWidth: .infinity)

                                Spacer()

                                // Picker on the right side
                                Picker(selection: Binding(
                                    get: { roundTargetToStep(state.target, targetStep) },
                                    set: { state.target = $0 }
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
                            }
                        }
                    }
                }
            }

            VStack {
                // Picker for ISF/CR settings
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

                                Spacer()

                                Divider().frame(width: 1, height: 20)

                                Spacer()

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

    private func roundOverridePercentageToStep() {
        // Check if overridePercentage is not divisible by the selected step
        if state.overridePercentage.truncatingRemainder(dividingBy: Double(percentageStep)) != 0 {
            let roundedValue: Double

            if state.overridePercentage > 100 {
                // Round down to the nearest valid step away from 100
                let stepCount = (state.overridePercentage - 100) / Double(percentageStep)
                roundedValue = 100 + floor(stepCount) * Double(percentageStep)
            } else {
                // Round up to the nearest valid step away from 100
                let stepCount = (100 - state.overridePercentage) / Double(percentageStep)
                roundedValue = 100 - floor(stepCount) * Double(percentageStep)
            }

            // Ensure the value stays between 10 and 200
            state.overridePercentage = max(10, min(roundedValue, 200))
        }
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
