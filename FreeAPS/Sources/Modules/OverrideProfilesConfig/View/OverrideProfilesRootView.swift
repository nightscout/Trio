import CoreData
import Foundation
import SwiftUI
import Swinject

extension OverrideProfilesConfig {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()
        @State private var isEditing = false
        @State private var showAlert = false
        @State private var showingDetail = false
        @State private var selectedPreset: OverridePresets?
        @State private var isEditSheetPresented: Bool = false
        @State private var alertSring = ""
        @State var isSheetPresented: Bool = false
        @State private var originalPreset: OverridePresets?
        @State private var showDeleteAlert = false
        @State private var indexToDelete: Int?
        @State private var profileNameToDelete: String = ""

        @Environment(\.dismiss) var dismiss
        @Environment(\.managedObjectContext) var moc

        @FetchRequest(
            entity: OverridePresets.entity(),
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)], predicate: NSPredicate(
                format: "name != %@", "" as String
            )
        ) var fetchedProfiles: FetchedResults<OverridePresets>

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

        var presetPopover: some View {
            Form {
                nameSection(header: "Enter a name")
                settingsSection(header: "Settings to save")
                Section {
                    Button("Save") {
                        state.savePreset()
                        isSheetPresented = false
                    }
                    .disabled(
                        state.profileName.isEmpty || fetchedProfiles
                            .contains(where: { $0.name == state.profileName })
                    )

                    Button("Cancel") {
                        isSheetPresented = false
                    }
                    .tint(.red)
                }
            }
        }

        var editPresetPopover: some View {
            Form {
                nameSection(header: "Change name?")
                settingsConfig(header: "Change settings")
                Section {
                    Button("Save") {
                        guard let selectedPreset = selectedPreset else { return }
                        state.updatePreset(selectedPreset)
                        isEditSheetPresented = false
                    }
                    .disabled(!hasChanges())

                    Button("Cancel") {
                        isEditSheetPresented = false
                    }
                    .tint(.red)
                }
            }
            .onAppear {
                if let preset = selectedPreset {
                    originalPreset = preset
                    state.populateSettings(from: preset)
                }
            }
        }

        @ViewBuilder private func nameSection(header: String) -> some View {
            Section {
                TextField("Profile override name", text: $state.profileName)
            } header: {
                Text(header)
            }
        }

        @ViewBuilder private func settingsConfig(header: String) -> some View {
            Section {
                VStack {
                    Slider(
                        value: $state.percentage,
                        in: 10 ... 200,
                        step: 1,
                        onEditingChanged: { editing in
                            isEditing = editing
                        }
                    ).accentColor(state.percentage >= 130 ? .red : .blue)
                    Text("\(state.percentage.formatted(.number)) %")
                        .foregroundColor(
                            state
                                .percentage >= 130 ? .red :
                                (isEditing ? .orange : .blue)
                        )
                        .font(.largeTitle)
                    Spacer()
                    Toggle(isOn: $state._indefinite) {
                        Text("Enable indefinitely")
                    }
                }
                if !state._indefinite {
                    HStack {
                        Text("Duration")
                        DecimalTextField("0", value: $state.duration, formatter: formatter, cleanInput: false)
                        Text("minutes").foregroundColor(.secondary)
                    }
                }

                HStack {
                    Toggle(isOn: $state.override_target) {
                        Text("Override Profile Target")
                    }
                }
                if state.override_target {
                    HStack {
                        Text("Target Glucose")
                        DecimalTextField("0", value: $state.target, formatter: glucoseFormatter, cleanInput: false)
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                }
                HStack {
                    Toggle(isOn: $state.advancedSettings) {
                        Text("More options")
                    }
                }
                if state.advancedSettings {
                    HStack {
                        Toggle(isOn: $state.smbIsOff) {
                            Text("Always Disable SMBs")
                        }
                    }
                    if !state.smbIsOff {
                        HStack {
                            Toggle(isOn: $state.smbIsScheduledOff) {
                                Text("Schedule when SMBs are Off")
                            }
                        }
                        if state.smbIsScheduledOff {
                            HStack {
                                Text("First Hour SMBs are Off (24 hours)")
                                DecimalTextField("0", value: $state.start, formatter: formatter, cleanInput: false)
                                Text("hour").foregroundColor(.secondary)
                            }
                            HStack {
                                Text("First Hour SMBs are Resumed (24 hours)")
                                DecimalTextField("0", value: $state.end, formatter: formatter, cleanInput: false)
                                Text("hour").foregroundColor(.secondary)
                            }
                        }
                    }
                    HStack {
                        Toggle(isOn: $state.isfAndCr) {
                            Text("Change ISF and CR")
                        }
                    }
                    if !state.isfAndCr {
                        HStack {
                            Toggle(isOn: $state.isf) {
                                Text("Change ISF")
                            }
                        }
                        HStack {
                            Toggle(isOn: $state.cr) {
                                Text("Change CR")
                            }
                        }
                    }
                    HStack {
                        Text("SMB Minutes")
                        DecimalTextField(
                            "0",
                            value: $state.smbMinutes,
                            formatter: formatter,
                            cleanInput: false
                        )
                        Text("minutes").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("UAM SMB Minutes")
                        DecimalTextField(
                            "0",
                            value: $state.uamMinutes,
                            formatter: formatter,
                            cleanInput: false
                        )
                        Text("minutes").foregroundColor(.secondary)
                    }
                }
            } header: {
                Text(header)
            }
        }

        @ViewBuilder private func settingsSection(header: String) -> some View {
            Section(header: Text(header)) {
                let percentString = Text("Override: \(Int(state.percentage))%")
                let targetString = state
                    .target != 0 ? Text("Target: \(state.target.formatted()) \(state.units.rawValue)") : Text("")
                let durationString = state
                    ._indefinite ? Text("Duration: Indefinite") : Text("Duration: \(state.duration.formatted()) minutes")
                let isfString = state.isf ? Text("Change ISF") : Text("")
                let crString = state.cr ? Text("Change CR") : Text("")
                let smbString = state.smbIsOff ? Text("Disable SMB") : Text("")
                let scheduledSMBString = state.smbIsScheduledOff ? Text("SMB Schedule On") : Text("")
                let maxMinutesSMBString = state
                    .smbMinutes != 0 ? Text("\(state.smbMinutes.formatted()) SMB Basal minutes") : Text("")
                let maxMinutesUAMString = state
                    .uamMinutes != 0 ? Text("\(state.uamMinutes.formatted()) UAM Basal minutes") : Text("")

                VStack(alignment: .leading, spacing: 2) {
                    percentString
                    if targetString != Text("") { targetString }
                    if durationString != Text("") { durationString }
                    if isfString != Text("") { isfString }
                    if crString != Text("") { crString }
                    if smbString != Text("") { smbString }
                    if scheduledSMBString != Text("") { scheduledSMBString }
                    if maxMinutesSMBString != Text("") { maxMinutesSMBString }
                    if maxMinutesUAMString != Text("") { maxMinutesUAMString }
                }
                .foregroundColor(.secondary)
                .font(.caption)
            }
        }

        var body: some View {
            Form {
                if state.presets.isNotEmpty {
                    Section {
                        ForEach(fetchedProfiles.indices, id: \.self) { index in
                            let preset = fetchedProfiles[index]
                            profilesView(for: preset)
                                .swipeActions {
                                    Button(role: .none) {
                                        indexToDelete = index
                                        profileNameToDelete = preset.name ?? "this profile"
                                        showDeleteAlert = true
                                    } label: {
                                        Label("Ta bort", systemImage: "trash")
                                    }.tint(.red)

                                    Button {
                                        selectedPreset = preset
                                        state.profileName = preset.name ?? ""
                                        isEditSheetPresented = true
                                    } label: {
                                        Label("Redigera", systemImage: "square.and.pencil")
                                    }.tint(.blue)
                                }
                        }
                    }
                    header: { Text("Activate profile override") }
                    footer: { VStack(alignment: .leading) {
                        Text("Swipe left on a profile to edit or delete it.")
                    }
                    }
                }
                settingsConfig(header: "Insulin")
                Section {
                    HStack {
                        Button("Start new Profile") {
                            showAlert.toggle()
                            alertSring = "\(state.percentage.formatted(.number)) %, " +
                                (
                                    state.duration > 0 || !state
                                        ._indefinite ?
                                        (
                                            state
                                                .duration
                                                .formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) +
                                                " min."
                                        ) :
                                        NSLocalizedString(" infinite duration.", comment: "")
                                ) +
                                (
                                    (state.target == 0 || !state.override_target) ? "" :
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
                                    "Starting this override will change your Profiles and/or your Target Glucose used for looping during the entire selected duration. Tapping ”Start Profile” will start your new profile or edit your current active profile.",
                                    comment: ""
                                )
                        }
                        .disabled(unChanged())
                        .buttonStyle(BorderlessButtonStyle())
                        .font(.callout)
                        .controlSize(.mini)
                        .alert(
                            "Start Profile",
                            isPresented: $showAlert,
                            actions: {
                                Button("Cancel", role: .cancel) { state.isEnabled = false }
                                Button("Start Profile", role: .destructive) {
                                    if state._indefinite { state.duration = 0 }
                                    state.isEnabled.toggle()
                                    state.saveSettings()
                                    dismiss()
                                }
                            },
                            message: {
                                Text(alertSring)
                            }
                        )
                        Button {
                            isSheetPresented = true
                        }
                        label: { Text("Save as Profile") }
                            .tint(.orange)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .buttonStyle(BorderlessButtonStyle())
                            .font(.callout)
                            .controlSize(.mini)
                            .disabled(unChanged())
                    }
                    .sheet(isPresented: $isSheetPresented) {
                        presetPopover
                    }
                }
                footer: {
                    Text(
                        "Your profile basal insulin will be adjusted with the override percentage and your profile ISF and CR will be inversly adjusted with the percentage."
                    )
                }

                Button("Return to Normal") {
                    state.cancelProfile()
                    dismiss()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .buttonStyle(BorderlessButtonStyle())
                .disabled(!state.isEnabled)
                .tint(.red)
            }
            .onAppear(perform: configureView)
            .onAppear { state.savedSettings() }
            .navigationBarTitle("Profiles")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: Button("Close", action: state.hideModal))
            .sheet(isPresented: $isEditSheetPresented) {
                editPresetPopover
                    .padding()
            }
            .alert(isPresented: $showDeleteAlert) {
                Alert(
                    title: Text("Delete profile override"),
                    message: Text("Are you sure you want to delete\n\(profileNameToDelete)?"),
                    primaryButton: .destructive(Text("Delete")) {
                        if let index = indexToDelete {
                            removeProfile(at: IndexSet(integer: index))
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }

        @ViewBuilder private func profilesView(for preset: OverridePresets) -> some View {
            let target = state.units == .mmolL ? (((preset.target ?? 0) as NSDecimalNumber) as Decimal)
                .asMmolL : (preset.target ?? 0) as Decimal
            let duration = (preset.duration ?? 0) as Decimal
            let name = ((preset.name ?? "") == "") || (preset.name?.isEmpty ?? true) ? "" : preset.name!
            let percent = preset.percentage / 100
            let perpetual = preset.indefinite
            let durationString = perpetual ? "" : "\(formatter.string(from: duration as NSNumber)!)"
            let scheduledSMBstring = (preset.smbIsOff && preset.smbIsScheduledOff) ? "Scheduled SMBs" : ""
            let smbString = (preset.smbIsOff && scheduledSMBstring == "") ? "SMBs are off" : ""
            let targetString = target != 0 ? "\(glucoseFormatter.string(from: target as NSNumber)!)" : ""
            let maxMinutesSMB = (preset.smbMinutes as Decimal?) != nil ? (preset.smbMinutes ?? 0) as Decimal : 0
            let maxMinutesUAM = (preset.uamMinutes as Decimal?) != nil ? (preset.uamMinutes ?? 0) as Decimal : 0
            let isfString = preset.isf ? "ISF" : ""
            let crString = preset.cr ? "CR" : ""
            let dash = crString != "" ? "/" : ""
            let isfAndCRstring = isfString + dash + crString

            if name != "" {
                HStack {
                    VStack {
                        HStack {
                            Text(name)
                            Spacer()
                        }
                        HStack(spacing: 5) {
                            Text(percent.formatted(.percent.grouping(.never).rounded().precision(.fractionLength(0))))
                            if targetString != "" {
                                Text(targetString)
                                Text(targetString != "" ? state.units.rawValue : "")
                            }
                            if durationString != "" { Text(durationString + (perpetual ? "" : "min")) }
                            if smbString != "" { Text(smbString).foregroundColor(.secondary).font(.caption) }
                            if scheduledSMBstring != "" { Text(scheduledSMBstring) }
                            if preset.advancedSettings {
                                Text(maxMinutesSMB == 0 ? "" : maxMinutesSMB.formatted() + " SMB")
                                Text(maxMinutesUAM == 0 ? "" : maxMinutesUAM.formatted() + " UAM")
                                Text(isfAndCRstring)
                            }
                            Spacer()
                        }
                        .padding(.top, 2)
                        .foregroundColor(.secondary)
                        .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        state.selectProfile(id_: preset.id ?? "")
                        state.hideModal()
                    }
                }
            }
        }

        private func unChanged() -> Bool {
            let defaultProfile = state.percentage == 100 && !state.override_target && !state.advancedSettings
            let noDurationSpecified = !state._indefinite && state.duration == 0
            let targetZeroWithOverride = state.override_target && state.target == 0
            let allSettingsDefault = state.percentage == 100 && !state.override_target && !state.smbIsOff && !state
                .smbIsScheduledOff && state.smbMinutes == state.defaultSmbMinutes && state.uamMinutes == state.defaultUamMinutes

            return defaultProfile || noDurationSpecified || targetZeroWithOverride || allSettingsDefault
        }

        private func hasChanges() -> Bool {
            guard let originalPreset = originalPreset else { return false }

            let targetInStateUnits: Decimal
            let targetInPresetUnits: Decimal

            if state.units == .mmolL {
                targetInStateUnits = state.target
                targetInPresetUnits = Decimal(Double(truncating: originalPreset.target ?? 0) * 0.0555)
            } else {
                targetInStateUnits = state.target
                targetInPresetUnits = (originalPreset.target ?? 0) as Decimal
            }

            let hasChanges = state.profileName != originalPreset.name ||
                state.percentage != originalPreset.percentage ||
                state.duration != (originalPreset.duration ?? 0) as Decimal ||
                state._indefinite != originalPreset.indefinite ||
                state.override_target != (originalPreset.target != nil) ||
                (state.override_target && targetInStateUnits != targetInPresetUnits) ||
                // state.advancedSettings != originalPreset.advancedSettings ||
                state.smbIsOff != originalPreset.smbIsOff ||
                state.smbIsScheduledOff != originalPreset.smbIsScheduledOff ||
                state.isf != originalPreset.isf ||
                state.cr != originalPreset.cr ||
                state.smbMinutes != (originalPreset.smbMinutes ?? 0) as Decimal ||
                state.uamMinutes != (originalPreset.uamMinutes ?? 0) as Decimal ||
                state.isfAndCr != originalPreset.isfAndCr ||
                state.start != (originalPreset.start ?? 0) as Decimal ||
                state.end != (originalPreset.end ?? 0) as Decimal

            return hasChanges
        }

        private func removeProfile(at offsets: IndexSet) {
            for index in offsets {
                let language = fetchedProfiles[index]
                moc.delete(language)
            }
            do {
                try moc.save()
            } catch {
                // To do: add error
            }
        }
    }
}

extension OverrideProfilesConfig.StateModel {
    func populateSettings(from preset: OverridePresets) {
        profileName = preset.name ?? ""
        percentage = preset.percentage
        duration = (preset.duration ?? 0) as Decimal
        _indefinite = preset.indefinite
        override_target = preset.target != nil
        if let targetValue = preset.target as Decimal? {
            target = units == .mmolL ? Decimal(Double(truncating: targetValue as NSNumber) * 0.0555) : targetValue
        } else {
            target = 0
        }
        advancedSettings = preset.advancedSettings
        smbIsOff = preset.smbIsOff
        smbIsScheduledOff = preset.smbIsScheduledOff
        isf = preset.isf
        cr = preset.cr
        smbMinutes = (preset.smbMinutes ?? 0) as Decimal
        uamMinutes = (preset.uamMinutes ?? 0) as Decimal
        isfAndCr = preset.isfAndCr
        start = (preset.start ?? 0) as Decimal
        end = (preset.end ?? 0) as Decimal
    }
}
