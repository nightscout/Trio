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

    @State private var hasChanges = false
    @State private var isEditing = false
    @State private var target_override = false
    @State private var showAlert = false
    @State private var displayPickerStart: Bool = false
    @State private var displayPickerEnd: Bool = false
    @State private var displayPickerSmbMinutes: Bool = false
    @State private var displayPickerUamMinutes: Bool = false

    init(overrideToEdit: OverrideStored, state: OverrideConfig.StateModel) {
        override = overrideToEdit
        _state = StateObject(wrappedValue: state)
        _name = State(initialValue: overrideToEdit.name ?? "")
        _percentage = State(initialValue: overrideToEdit.percentage)
        _indefinite = State(initialValue: overrideToEdit.indefinite)
        _duration = State(initialValue: overrideToEdit.duration?.decimalValue ?? 0)
        _target = State(
            initialValue: state.units == .mgdL ? overrideToEdit.target?.decimalValue : overrideToEdit.target?
                .decimalValue.asMmolL
        )
        _target_override = State(initialValue: overrideToEdit.target?.decimalValue != 0)
        _advancedSettings = State(initialValue: overrideToEdit.advancedSettings)
        _smbIsOff = State(initialValue: overrideToEdit.smbIsOff)
        _smbIsScheduledOff = State(initialValue: overrideToEdit.smbIsScheduledOff)
        _start = State(initialValue: overrideToEdit.start?.decimalValue)
        _end = State(initialValue: overrideToEdit.end?.decimalValue)
        _isfAndCr = State(initialValue: overrideToEdit.isfAndCr)
        _isf = State(initialValue: overrideToEdit.isf)
        _cr = State(initialValue: overrideToEdit.cr)
        _smbMinutes = State(initialValue: overrideToEdit.smbMinutes?.decimalValue)
        _uamMinutes = State(initialValue: overrideToEdit.uamMinutes?.decimalValue)
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
            Form {
                editOverride()

                saveButton

            }.scrollContentBackground(.hidden).background(color)
                .navigationTitle("Edit Override")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading: Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                })
                .onDisappear {
                    if !hasChanges {
                        // Reset UI changes
                        resetValues()
                    }
                }
                .alert(isPresented: $state.showInvalidTargetAlert) {
                    Alert(
                        title: Text("Invalid Input"),
                        message: Text("\(state.alertMessage)"),
                        dismissButton: .default(Text("OK")) { state.showInvalidTargetAlert = false }
                    )
                }
        }
    }

    @ViewBuilder private func editOverride() -> some View {
        if override.name != nil {
            Section {
                VStack {
                    TextField("Name", text: $name)
                        .onChange(of: name) { _ in hasChanges = true }
                }
            } header: {
                Text("Name")
            }.listRowBackground(Color.chart)
        }
        Section {
            VStack {
                Spacer()
                Text("\(percentage.formatted(.number)) %")
                    .foregroundColor(
                        state
                            .overrideSliderPercentage >= 130 ? .red :
                            (isEditing ? .orange : Color.tabBar)
                    )
                    .font(.largeTitle)
                Slider(
                    value: $percentage,
                    in: 10 ... 200,
                    step: 1
                ).onChange(of: percentage) { _ in hasChanges = true }
                Spacer()
                Toggle(isOn: $indefinite) {
                    Text("Enable Indefinitely")
                }.onChange(of: indefinite) { _ in hasChanges = true }
            }
            if !indefinite {
                HStack {
                    Text("Duration")
                    TextFieldWithToolBar(
                        text: Binding(
                            get: { duration },
                            set: {
                                duration = $0
                                hasChanges = true
                            }
                        ),
                        placeholder: "0",
                        numberFormatter: formatter
                    )
                    Text("minutes").foregroundColor(.secondary)
                }
            }

            HStack {
                Toggle(isOn: $target_override) {
                    Text("Override Override Target")
                }.onChange(of: target_override) { _ in
                    hasChanges = true
                }
            }
            if target_override {
                HStack {
                    Text("Target Glucose")
                    TextFieldWithToolBar(text: Binding(
                        get: {
                            target ?? 0
                        },
                        set: {
                            target = $0
                            hasChanges = true
                        }
                    ), placeholder: "0", numberFormatter: glucoseFormatter)
                    Text(state.units.rawValue).foregroundColor(.secondary)
                }
            }

            Toggle(isOn: $advancedSettings) {
                Text("More Options")
            }.onChange(of: advancedSettings) { _ in hasChanges = true }

            if advancedSettings {
                Toggle(
                    isOn: Binding(
                        get: { smbIsOff },
                        set: { newValue in
                            smbIsOff = newValue
                            if newValue {
                                smbIsScheduledOff = false
                            }
                            hasChanges = true
                        }
                    )
                ) {
                    Text("Disable SMBs")
                }

                Toggle(
                    isOn: Binding(
                        get: { smbIsScheduledOff },
                        set: { newValue in
                            smbIsScheduledOff = newValue
                            if newValue {
                                smbIsOff = false
                            }
                            hasChanges = true
                        }
                    )
                ) {
                    Text("Schedule When SMBs Are Disabled")
                }

                if smbIsScheduledOff {
                    // First Hour SMBs Are Disabled
                    VStack {
                        HStack {
                            Text("First Hour SMBs Are Disabled")
                            Spacer()

                            // Display current selection based on format
                            Text(
                                is24HourFormat() ? format24Hour(Int(truncating: start! as NSNumber)) + ":00" :
                                    convertTo12HourFormat(Int(truncating: start! as NSNumber))
                            )
                            .foregroundColor(!displayPickerStart ? .primary : .accentColor)
                        }
                        .onTapGesture {
                            displayPickerStart.toggle() // Toggle the picker visibility
                        }

                        // Show picker if toggled
                        if displayPickerStart {
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
                            .pickerStyle(WheelPickerStyle()) // Use wheel style
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top)

                    // First Hour SMBs Are Resumed
                    VStack {
                        HStack {
                            Text("First Hour SMBs Are Resumed")
                            Spacer()

                            // Display current selection based on format
                            Text(
                                is24HourFormat() ? format24Hour(Int(truncating: end! as NSNumber)) + ":00" :
                                    convertTo12HourFormat(Int(truncating: end! as NSNumber))
                            )
                            .foregroundColor(!displayPickerEnd ? .primary : .accentColor)
                        }
                        .onTapGesture {
                            displayPickerEnd.toggle() // Toggle the picker visibility
                        }

                        // Show picker if toggled
                        if displayPickerEnd {
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
                            .pickerStyle(WheelPickerStyle()) // Use wheel style
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top)
                }

                Toggle(isOn: $isfAndCr) {
                    Text("Change ISF and CR")
                }.onChange(of: isfAndCr) { _ in hasChanges = true }

                if !isfAndCr {
                    Toggle(isOn: $isf) {
                        Text("Change ISF")
                    }.onChange(of: isf) { _ in hasChanges = true }

                    Toggle(isOn: $cr) {
                        Text("Change CR")
                    }.onChange(of: cr) { _ in hasChanges = true }
                }

                if !smbIsOff {
                    // SMB Minutes Picker
                    VStack {
                        HStack {
                            Text("Max SMB Minutes")
                            Spacer()
                            Text("\(smbMinutes?.formatted(.number) ?? "\(state.defaultSmbMinutes)") min")
                                .foregroundColor(!displayPickerSmbMinutes ? .primary : .accentColor)
                        }
                        .onTapGesture {
                            displayPickerSmbMinutes.toggle()
                        }

                        if displayPickerSmbMinutes {
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
                        }
                    }
                    .padding(.top)

                    // UAM SMB Minutes Picker
                    VStack {
                        HStack {
                            Text("Max UAM SMB Minutes")
                            Spacer()
                            Text("\(uamMinutes?.formatted(.number) ?? "\(state.defaultUamMinutes)") min")
                                .foregroundColor(!displayPickerUamMinutes ? .primary : .accentColor)
                        }
                        .onTapGesture {
                            displayPickerUamMinutes.toggle()
                        }

                        if displayPickerUamMinutes {
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
                    .padding(.top)
                }
            }
        }.listRowBackground(Color.chart)
    }

    private var saveButton: some View {
        HStack {
            Spacer()
            Button(action: {
                if !state.isInputInvalid(target: target ?? 0) {
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
                            }
                        }

                        // Update View
                        state.updateLatestOverrideConfiguration()
                        hasChanges = false
                        presentationMode.wrappedValue.dismiss()
                    } catch {
                        debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to edit Override")
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
}
