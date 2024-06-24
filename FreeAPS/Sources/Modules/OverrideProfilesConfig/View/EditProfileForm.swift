import Foundation
import SwiftUI

struct EditProfileForm: View {
//    @Injected() var settingsManager: SettingsManager!
    @ObservedObject var profile: OverrideStored
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @StateObject var state: OverrideProfilesConfig.StateModel

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

    init(profile: OverrideStored, state: OverrideProfilesConfig.StateModel) {
        self.profile = profile
        _state = StateObject(wrappedValue: state)
        _name = State(initialValue: profile.name ?? "")
        _percentage = State(initialValue: profile.percentage)
        _indefinite = State(initialValue: profile.indefinite)
        _duration = State(initialValue: profile.duration?.decimalValue ?? 0)
        _target = State(initialValue: profile.target?.decimalValue)
        _target_override = State(initialValue: profile.target?.decimalValue != 0)
        _advancedSettings = State(initialValue: profile.advancedSettings)
        _smbIsOff = State(initialValue: profile.smbIsOff)
        _smbIsAlwaysOff = State(initialValue: profile.smbIsAlwaysOff)
        _start = State(initialValue: profile.start?.decimalValue)
        _end = State(initialValue: profile.end?.decimalValue)
        _isfAndCr = State(initialValue: profile.isfAndCr)
        _isf = State(initialValue: profile.isf)
        _cr = State(initialValue: profile.cr)
        _smbMinutes = State(initialValue: profile.smbMinutes?.decimalValue)
        _uamMinutes = State(initialValue: profile.uamMinutes?.decimalValue)
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
                editProfile()

                saveButton

            }.scrollContentBackground(.hidden).background(color)
                .navigationTitle("Edit Profile")
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
        }
    }

    @ViewBuilder private func editProfile() -> some View {
        if profile.name != nil {
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
                            .percentageProfiles >= 130 ? .red :
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
                    Text("Override Profile Target")
                }.onChange(of: target_override) { _ in
                    hasChanges = true
                }
            }
            if target_override {
                HStack {
                    Text("Target Glucose")
                    TextFieldWithToolBar(text: Binding(
                        get: { target ?? 0 },
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
                saveChanges()
                do {
                    try profile.managedObjectContext?.save()
                    hasChanges = false
                    presentationMode.wrappedValue.dismiss()
                } catch {
                    debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to edit Profile")
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
        if !profile.isPreset, hasChanges, name == (profile.name ?? "") {
            profile.name = "Custom Override"
        } else {
            profile.name = name
        }
        profile.percentage = percentage
        profile.indefinite = indefinite
        profile.duration = NSDecimalNumber(decimal: duration)
        if target_override {
            profile.target = target.map { NSDecimalNumber(decimal: $0) }
        } else {
            profile.target = 0
        }
        profile.advancedSettings = advancedSettings
        profile.smbIsOff = smbIsOff
        profile.smbIsAlwaysOff = smbIsAlwaysOff
        profile.start = start.map { NSDecimalNumber(decimal: $0) }
        profile.end = end.map { NSDecimalNumber(decimal: $0) }
        profile.isfAndCr = isfAndCr
        profile.isf = isf
        profile.cr = cr
        profile.smbMinutes = smbMinutes.map { NSDecimalNumber(decimal: $0) }
        profile.uamMinutes = uamMinutes.map { NSDecimalNumber(decimal: $0) }
        state.scheduleOverrideDisabling(for: profile)
    }

    private func resetValues() {
        name = profile.name ?? ""
        percentage = profile.percentage
        indefinite = profile.indefinite
        duration = profile.duration?.decimalValue ?? 0
        target = profile.target?.decimalValue
        advancedSettings = profile.advancedSettings
        smbIsOff = profile.smbIsOff
        smbIsAlwaysOff = profile.smbIsAlwaysOff
        start = profile.start?.decimalValue
        end = profile.end?.decimalValue
        isfAndCr = profile.isfAndCr
        isf = profile.isf
        cr = profile.cr
        smbMinutes = profile.smbMinutes?.decimalValue ?? state.defaultSmbMinutes
        uamMinutes = profile.uamMinutes?.decimalValue ?? state.defaultUamMinutes
    }
}
