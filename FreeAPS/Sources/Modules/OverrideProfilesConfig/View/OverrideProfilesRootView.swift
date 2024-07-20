import CoreData
import Foundation
import SwiftUI
import Swinject

extension OverrideProfilesConfig {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()

        @State private var isEditing = false
        @State private var showOverrideCreationSheet = false
        @State private var showingDetail = false
        @State private var showCheckmark: Bool = false
        @State private var selectedPresetID: String?
        @State private var selectedOverride: OverrideStored?
        // temp targets
        @State private var isPromptPresented = false
        @State private var isRemoveAlertPresented = false
        @State private var removeAlert: Alert?
        @State private var isEditingTT = false

        @Environment(\.managedObjectContext) var moc
        @Environment(\.colorScheme) var colorScheme
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

        @FetchRequest(
            entity: TempTargetsSlider.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var isEnabledArray: FetchedResults<TempTargetsSlider>

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

<<<<<<< HEAD
        var body: some View {
            VStack {
                Picker("Tab", selection: $state.selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Text(NSLocalizedString(tab.name, comment: "")).tag(tab)
                    }
                }
                .pickerStyle(.segmented).padding(.horizontal, 10)
=======
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
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133

                Form {
                    switch state.selectedTab {
                    case .overrides: overrides()
                    case .tempTargets: tempTargets() }
                }.scrollContentBackground(.hidden).background(color)
                    .onAppear(perform: configureView)
                    .navigationBarTitle("Adjustments")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            switch state.selectedTab {
                            case .overrides:
                                Button(action: {
                                    showOverrideCreationSheet = true
                                }, label: {
                                    HStack {
                                        Text("Add Override")
                                        Image(systemName: "plus")
                                    }
                                })
                            default:
                                EmptyView()
                            }
                        }
                    }
<<<<<<< HEAD
                    .sheet(isPresented: $state.showOverrideEditSheet, onDismiss: {
                        Task {
                            await state.resetStateVariables()
                            state.showOverrideEditSheet = false
                        }

                    }) {
                        if let override = selectedOverride {
                            EditOverrideForm(overrideToEdit: override, state: state)
                        }
                    }
                    .sheet(isPresented: $showOverrideCreationSheet, onDismiss: {
                        Task {
                            await state.resetStateVariables()
                            showOverrideCreationSheet = false
                        }
                    }) {
                        AddOverrideForm(state: state)
                    }
            }.background(color)
        }

        @ViewBuilder func overrides() -> some View {
            if state.overridePresets.isNotEmpty {
                overridePresets
            } else {
                defaultText
            }

            if state.isEnabled, state.activeOverrideName.isNotEmpty {
                currentActiveOverride
            }

            if state.overridePresets.isNotEmpty || state.currentActiveOverride != nil {
                cancelOverrideButton
            }
        }

        private var defaultText: some View {
            Section {} header: {
                Text("Add Preset or Override by tapping the '+'").foregroundStyle(.secondary)
            }
        }

        private var overridePresets: some View {
            Section {
                ForEach(state.overridePresets) { preset in
                    overridesView(for: preset)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .none) {
                                Task {
                                    await state.invokeOverridePresetDeletion(preset.objectID)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .tint(.red)
                            }
                            Button(action: {
                                // Set the selected Override to the chosen Preset and pass it to the Edit Sheet
                                selectedOverride = preset
                                state.showOverrideEditSheet = true
                            }, label: {
                                Label("Edit", systemImage: "pencil")
                                    .tint(.blue)
                            })
                        }
                }
                .onMove(perform: state.reorderOverride)
                .listRowBackground(Color.chart)
            } header: {
                Text("Presets")
            } footer: {
                HStack {
                    Image(systemName: "hand.draw.fill")
                    Text("Swipe left to edit or delete an override preset. Hold, drag and drop to reorder a preset.")
=======
                    .tint(.red)
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
                }
            }
        }

<<<<<<< HEAD
        private var currentActiveOverride: some View {
            Section {
                HStack {
                    Text("\(state.activeOverrideName) is running")

                    Spacer()
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(Color.blue)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    Task {
                        /// To avoid editing the Preset when a Preset-Override is running we first duplicate the Preset-Override as a non-Preset Override
                        /// The currentActiveOverride variable in the State will update automatically via MOC notification
                        await state.duplicateOverridePresetAndCancelPreviousOverride()

                        /// selectedOverride is used for passing the chosen Override to the EditSheet so we have to set the updated currentActiveOverride to be the selectedOverride
                        selectedOverride = state.currentActiveOverride

                        /// Now we can show the Edit sheet
                        state.showOverrideEditSheet = true
                    }
                }
            }
            .listRowBackground(Color.blue.opacity(0.2))
        }

        private var cancelOverrideButton: some View {
            Button(action: {
                Task {
                    // Save cancelled Override in OverrideRunStored Entity
                    // Cancel ALL active Override
                    await state.disableAllActiveOverrides(createOverrideRunEntry: true)
                }
            }, label: {
                Text("Cancel Override")

            })
                .frame(maxWidth: .infinity, alignment: .center)
                .disabled(!state.isEnabled)
                .listRowBackground(!state.isEnabled ? Color(.systemGray4) : Color(.systemRed))
                .tint(.white)
        }

        @ViewBuilder func tempTargets() -> some View {
            if !state.presetsTT.isEmpty {
                Section(header: Text("Presets")) {
                    ForEach(state.presetsTT) { preset in
                        presetView(for: preset)
                    }
                }.listRowBackground(Color.chart)
            }

            HStack {
                Text("Experimental")
                Toggle(isOn: $state.viewPercantage) {}.controlSize(.mini)
                Image(systemName: "figure.highintensity.intervaltraining")
                Image(systemName: "fork.knife")
            }.listRowBackground(Color.chart)

            if state.viewPercantage {
                Section {
                    VStack {
                        Text("\(state.percentageTT.formatted(.number)) % Insulin")
                            .foregroundColor(isEditingTT ? .orange : .blue)
                            .font(.largeTitle)
                            .padding(.vertical)
                        Slider(
                            value: $state.percentageTT,
                            in: 15 ...
                                min(Double(state.maxValue * 100), 200),
                            step: 1,
                            onEditingChanged: { editing in
                                isEditingTT = editing
                            }
                        )
                        // Only display target slider when not 100 %
                        if state.percentageTT != 100 {
                            Spacer()
                            Divider()
                            Text(
=======
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
            .onDisappear {
                state.savedSettings()
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
                    Spacer()
                    Text("\(state.percentage.formatted(.number)) %")
                        .foregroundColor(
                            state
                                .percentage >= 130 ? .red :
                                (isEditing ? .orange : .blue)
                        )
                        .font(.largeTitle)
                    Slider(
                        value: $state.percentage,
                        in: 10 ... 200,
                        step: 1,
                        onEditingChanged: { editing in
                            isEditing = editing
                        }
                    ).accentColor(state.percentage >= 130 ? .red : .blue)
                    Spacer()
                    Toggle(isOn: $state._indefinite) {
                        Text("Enable indefinitely")
                    }
                }
                if !state._indefinite {
                    HStack {
                        Text("Duration")
                        TextFieldWithToolBar(text: $state.duration, placeholder: "0", numberFormatter: formatter)
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
                        TextFieldWithToolBar(text: $state.target, placeholder: "0", numberFormatter: glucoseFormatter)
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
                                TextFieldWithToolBar(text: $state.start, placeholder: "0", numberFormatter: formatter)
                                Text("hour").foregroundColor(.secondary)
                            }
                            HStack {
                                Text("First Hour SMBs are Resumed (24 hours)")
                                TextFieldWithToolBar(text: $state.end, placeholder: "0", numberFormatter: formatter)
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
                        TextFieldWithToolBar(text: $state.smbMinutes, placeholder: "0", numberFormatter: formatter)
                        Text("minutes").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("UAM SMB Minutes")
                        TextFieldWithToolBar(text: $state.uamMinutes, placeholder: "0", numberFormatter: formatter)
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
                                        Label("Delete", systemImage: "trash")
                                    }.tint(.red)

                                    Button {
                                        selectedPreset = preset
                                        state.profileName = preset.name ?? ""
                                        isEditSheetPresented = true
                                    } label: {
                                        Label("Edit", systemImage: "square.and.pencil")
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
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
                                (
                                    state
                                        .units == .mmolL ?
                                        "\(state.computeTarget().asMmolL.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))) mmol/L" :
                                        "\(state.computeTarget().formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))) mg/dl"
                                )
                                    + NSLocalizedString(" Target Glucose", comment: "")
                            )
                            .foregroundColor(.green)
                            .padding(.vertical)

                            Slider(
                                value: $state.hbt,
                                in: 101 ... 295,
                                step: 1
                            ).accentColor(.green)
                        }
<<<<<<< HEAD
                    }
                }.listRowBackground(Color.chart)
            } else {
                Section(header: Text("Custom")) {
                    HStack {
                        Text("Target")
                        Spacer()
                        TextFieldWithToolBar(text: $state.low, placeholder: "0", numberFormatter: formatter)
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Duration")
                        Spacer()
                        TextFieldWithToolBar(text: $state.durationTT, placeholder: "0", numberFormatter: formatter)
                        Text("minutes").foregroundColor(.secondary)
                    }
                    DatePicker("Date", selection: $state.date)
                    HStack {
                        Button { state.enact() }
                        label: { Text("Enact") }
                            .disabled(state.durationTT == 0)
                            .buttonStyle(BorderlessButtonStyle())
                            .font(.callout)
                            .controlSize(.mini)

                        Button { isPromptPresented = true }
                        label: { Text("Save as preset") }
                            .disabled(state.durationTT == 0)
=======
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
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
                            .tint(.orange)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .buttonStyle(BorderlessButtonStyle())
                            .font(.callout)
                            .controlSize(.mini)
<<<<<<< HEAD
                    }
                }.listRowBackground(Color.chart)
            }
            if state.viewPercantage {
                Section {
                    HStack {
                        Text("Duration")
                        Spacer()
                        TextFieldWithToolBar(text: $state.durationTT, placeholder: "0", numberFormatter: formatter)
                        Text("minutes").foregroundColor(.secondary)
                    }
                    DatePicker("Date", selection: $state.date)
                    HStack {
                        Button { state.enact() }
                        label: { Text("Enact") }
                            .disabled(state.durationTT == 0)
                            .buttonStyle(BorderlessButtonStyle())
                            .font(.callout)
                            .controlSize(.mini)

                        Button { isPromptPresented = true }
                        label: { Text("Save as preset") }
                            .disabled(state.durationTT == 0)
                            .tint(.orange)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .buttonStyle(BorderlessButtonStyle())
                            .controlSize(.mini)
                    }
                }.listRowBackground(Color.chart)
            }
=======
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
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133

            Section {
                Button { state.cancel() }
                label: {
                    HStack {
                        Spacer()
                        Text("Cancel Temp Target")
                        Spacer()
                        Image(systemName: "xmark.app")
                            .font(.title)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .disabled(state.storage.current() == nil)
                .listRowBackground(state.storage.current() == nil ? Color(.systemGray4) : Color(.systemRed))
                .tint(.white)
            }.popover(isPresented: $isPromptPresented) {
                Form {
                    Section(header: Text("Enter preset name")) {
                        TextField("Name", text: $state.newPresetName)
                        Button {
                            state.save()
                            isPromptPresented = false
                        }
                        label: { Text("Save") }
                        Button { isPromptPresented = false }
                        label: { Text("Cancel") }
                    }
                }
            }
            .onAppear {
                configureView()
                state.hbt = isEnabledArray.first?.hbt ?? 160
            }
<<<<<<< HEAD
        }

        private func presetView(for preset: TempTarget) -> some View {
            var low = preset.targetBottom
            var high = preset.targetTop
            if state.units == .mmolL {
                low = low?.asMmolL
                high = high?.asMmolL
            }
            let isSelected = preset.id == selectedPresetID

            return ZStack(alignment: .trailing, content: {
                HStack {
                    VStack {
                        HStack {
                            Text(preset.displayName)
                            Spacer()
                        }
                        HStack(spacing: 2) {
                            Text(
                                "\(formatter.string(from: (low ?? 0) as NSNumber)!) - \(formatter.string(from: (high ?? 0) as NSNumber)!)"
                            )
                            .foregroundColor(.secondary)
                            .font(.caption)

                            Text(state.units.rawValue)
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("for")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("\(formatter.string(from: preset.duration as NSNumber)!)")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("min")
                                .foregroundColor(.secondary)
                                .font(.caption)

                            Spacer()
                        }.padding(.top, 2)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        state.enactPreset(id: preset.id)
                        selectedPresetID = preset.id
                        showCheckmark.toggle()

                        // deactivate showCheckmark after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            showCheckmark = false
                        }
                    }

                    Image(systemName: "xmark.circle").foregroundColor(showCheckmark && isSelected ? Color.clear : Color.secondary)
                        .contentShape(Rectangle())
                        .padding(.vertical)
                        .onTapGesture {
                            removeAlert = Alert(
                                title: Text("Are you sure?"),
                                message: Text("Delete preset \"\(preset.displayName)\""),
                                primaryButton: .destructive(Text("Delete"), action: { state.removePreset(id: preset.id) }),
                                secondaryButton: .cancel()
                            )
                            isRemoveAlertPresented = true
                        }
                        .alert(isPresented: $isRemoveAlertPresented) {
                            removeAlert!
                        }
                }
                if showCheckmark && isSelected {
                    // show checkmark to indicate if the preset was actually pressed
                    Image(systemName: "checkmark.circle.fill")
                        .imageScale(.large)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.green)
                }
            })
        }

        @ViewBuilder private func overridesView(for preset: OverrideStored) -> some View {
            let target = state.units == .mmolL ? (((preset.target ?? 0) as NSDecimalNumber) as Decimal)
                .asMmolL : (preset.target ?? 0) as Decimal
            let duration = (preset.duration ?? 0) as Decimal
            let name = ((preset.name ?? "") == "") || (preset.name?.isEmpty ?? true) ? "" : preset.name!
            let percent = preset.percentage / 100
            let perpetual = preset.indefinite
            let durationString = perpetual ? "" : "\(formatter.string(from: duration as NSNumber)!)"
            let scheduledSMBstring = (preset.smbIsOff && preset.smbIsAlwaysOff) ? "Scheduled SMBs" : ""
            let smbString = (preset.smbIsOff && scheduledSMBstring == "") ? "SMBs are off" : ""
            let targetString = target != 0 ? "\(glucoseFormatter.string(from: target as NSNumber)!)" : ""
            let maxMinutesSMB = (preset.smbMinutes as Decimal?) != nil ? (preset.smbMinutes ?? 0) as Decimal : 0
            let maxMinutesUAM = (preset.uamMinutes as Decimal?) != nil ? (preset.uamMinutes ?? 0) as Decimal : 0
            let isfString = preset.isf ? "ISF" : ""
            let crString = preset.cr ? "CR" : ""
            let dash = crString != "" ? "/" : ""
            let isfAndCRstring = isfString + dash + crString
            let isSelected = preset.id == selectedPresetID

            if name != "" {
                ZStack(alignment: .trailing, content: {
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
=======
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
            let data = state.profileViewData(for: preset)

            if data.name != "" {
                HStack {
                    VStack {
                        HStack {
                            Text(data.name)
                            Spacer()
                        }
                        HStack(spacing: 5) {
                            Text(data.percent.formatted(.percent.grouping(.never).rounded().precision(.fractionLength(0))))
                            if data.targetString != "" {
                                Text(data.targetString)
                                Text(data.targetString != "" ? state.units.rawValue : "")
                            }
                            if data.durationString != "" { Text(data.durationString + (data.perpetual ? "" : "min")) }
                            if data.smbString != "" { Text(data.smbString).foregroundColor(.secondary).font(.caption) }
                            if data.scheduledSMBString != "" { Text(data.scheduledSMBString) }
                            if preset.advancedSettings {
                                Text(data.maxMinutesSMB == 0 ? "" : data.maxMinutesSMB.formatted() + " SMB")
                                Text(data.maxMinutesUAM == 0 ? "" : data.maxMinutesUAM.formatted() + " UAM")
                                Text(data.isfAndCRString)
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
                            }
                            .padding(.top, 2)
                            .foregroundColor(.secondary)
                            .font(.caption)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                let objectID = preset.objectID
                                await state.enactOverridePreset(withID: objectID)
                                state.hideModal()
                                showCheckmark.toggle()
                                selectedPresetID = preset.id

<<<<<<< HEAD
                                // deactivate showCheckmark after 3 seconds
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                    showCheckmark = false
                                }
                            }
                        }
                    }
                    // show checkmark to indicate if the preset was actually pressed
                    if showCheckmark && isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .imageScale(.large)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.green)
                    } else {
                        Image(systemName: "line.3.horizontal")
                            .imageScale(.medium)
                            .foregroundStyle(.secondary)
                    }
                })
=======
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
                targetInPresetUnits = (originalPreset.target as NSDecimalNumber?)?.decimalValue.asMmolL ?? 0
            } else {
                targetInStateUnits = state.target
                targetInPresetUnits = (originalPreset.target as NSDecimalNumber?)?.decimalValue ?? 0
            }

            let hasChanges = state.profileName != originalPreset.name ||
                state.percentage != originalPreset.percentage ||
                state.duration != (originalPreset.duration ?? 0) as Decimal ||
                state._indefinite != originalPreset.indefinite ||
                state.override_target != (originalPreset.target != nil) ||
                (state.override_target && targetInStateUnits != targetInPresetUnits) ||
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
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
            }
        }
    }
}
