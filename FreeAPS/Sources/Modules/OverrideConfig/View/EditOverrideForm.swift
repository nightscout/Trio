import Foundation
import SwiftUI

struct EditOverrideForm: View {
    var override: OverrideStored
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState
    @Bindable var state: OverrideConfig.StateModel

    @State private var name: String
    @State private var percentage: Double
    @State private var indefinite: Bool
    @State private var duration: Decimal
    @State private var target: Decimal?
    @State private var advancedSettings: Bool
    @State private var smbIsOff: Bool
    @State private var smbIsAlwaysOff: Bool
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

    init(overrideToEdit: OverrideStored, state: OverrideConfig.StateModel) {
        override = overrideToEdit
        _state = Bindable(wrappedValue: state)
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
        _smbIsAlwaysOff = State(initialValue: overrideToEdit.smbIsAlwaysOff)
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

            }.scrollContentBackground(.hidden)
                .background(appState.trioBackgroundColor(for: colorScheme))
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
                    Text("Enable indefinitely")
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
                Text("More options")
            }.onChange(of: advancedSettings) { _ in hasChanges = true }

            if advancedSettings {
                Toggle(isOn: $smbIsOff) {
                    Text("Disable SMBs")
                }.onChange(of: smbIsOff) { _ in hasChanges = true }

                Toggle(isOn: $smbIsAlwaysOff) {
                    Text("Schedule when SMBs are Off")
                }.onChange(of: smbIsAlwaysOff) { _ in hasChanges = true }

                if smbIsAlwaysOff {
                    HStack {
                        Text("First Hour SMBs are Off (24 hours)")
                        TextFieldWithToolBar(
                            text: Binding(
                                get: { start ?? 0 },
                                set: {
                                    start = $0
                                    hasChanges = true
                                }
                            ),
                            placeholder: "0",
                            numberFormatter: formatter
                        )
                        Text("hour").foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Last Hour SMBs are Off (24 hours)")
                        TextFieldWithToolBar(
                            text: Binding(
                                get: { end ?? 23 },
                                set: {
                                    end = $0
                                    hasChanges = true
                                }
                            ),
                            placeholder: "0",
                            numberFormatter: formatter
                        )
                        Text("hour").foregroundColor(.secondary)
                    }
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

                HStack {
                    Text("SMB Minutes")
                    TextFieldWithToolBar(
                        text: Binding(
                            get: { smbMinutes ?? state.defaultSmbMinutes },
                            set: {
                                smbMinutes = $0
                                hasChanges = true
                            }
                        ),
                        placeholder: "0",
                        numberFormatter: formatter
                    )
                    Text("minutes").foregroundColor(.secondary)
                }

                HStack {
                    Text("UAM SMB Minutes")
                    TextFieldWithToolBar(
                        text: Binding(
                            get: { uamMinutes ?? state.defaultUamMinutes },
                            set: {
                                uamMinutes = $0
                                hasChanges = true
                            }
                        ),
                        placeholder: "0",
                        numberFormatter: formatter
                    )
                    Text("minutes").foregroundColor(.secondary)
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
                        Task {
                            await state.nightscoutManager.uploadProfiles()
                        }
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
        override.smbIsAlwaysOff = smbIsAlwaysOff
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
        smbIsAlwaysOff = override.smbIsAlwaysOff
        start = override.start?.decimalValue
        end = override.end?.decimalValue
        isfAndCr = override.isfAndCr
        isf = override.isf
        cr = override.cr
        smbMinutes = override.smbMinutes?.decimalValue ?? state.defaultSmbMinutes
        uamMinutes = override.uamMinutes?.decimalValue ?? state.defaultUamMinutes
    }
}
