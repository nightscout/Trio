import CoreData
import SwiftUI
import Swinject

extension OverrideConfig {
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
        @State private var isConfirmDeleteShown = false
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

        var body: some View {
            VStack {
                Picker("Tab", selection: $state.selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Text(NSLocalizedString(tab.name, comment: "")).tag(tab)
                    }
                }
                .pickerStyle(.segmented).padding(.horizontal, 10)

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
                Text("Add Preset or Override by tapping 'Add Override +' in the top right-hand corner of the screen.")
                    .textCase(nil)
                    .foregroundStyle(.secondary)
            }
        }

        private var overridePresets: some View {
            Section {
                ForEach(state.overridePresets) { preset in
                    overridesView(for: preset)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .none) {
                                selectedOverride = preset
                                isConfirmDeleteShown = true
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
                .confirmationDialog(
                    "Delete the Override Preset \"\(selectedOverride?.name ?? "")\"?",
                    isPresented: $isConfirmDeleteShown,
                    titleVisibility: .visible
                ) {
                    if let itemToDelete = selectedOverride {
                        Button(
                            state.currentActiveOverride == selectedOverride ? "Stop and Delete" : "Delete",
                            role: .destructive
                        ) {
                            if state.currentActiveOverride == selectedOverride {
                                Task {
                                    // Save cancelled Override in OverrideRunStored Entity
                                    // Cancel ALL active Override
                                    await state.disableAllActiveOverrides(createOverrideRunEntry: true)
                                }
                            }
                            // Perform the delete action
                            Task {
                                await state.invokeOverridePresetDeletion(itemToDelete.objectID)
                            }
                            // Reset the selected item after deletion
                            selectedOverride = nil
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        // Dismiss the dialog without action
                        selectedOverride = nil
                    }
                } message: {
                    if state.currentActiveOverride == selectedOverride {
                        Text(
                            state
                                .currentActiveOverride == selectedOverride ?
                                "This override preset is currently running. Deleting will stop it." : ""
                        )
                    }
                }
                .listRowBackground(Color.chart)
            } header: {
                Text("Presets")
            } footer: {
                HStack {
                    Image(systemName: "hand.draw.fill")
                    Text("Swipe left to edit or delete an override preset. Hold, drag and drop to reorder a preset.")
                }
            }
        }

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
                Text("Stop Override")

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
                    }
                }.listRowBackground(Color.chart)
            } else {
                Section(header: Text("Custom")) {
                    HStack {
                        Text("Target")
                        Spacer()
                        TextFieldWithToolBar(text: $state.low, placeholder: "0", numberFormatter: glucoseFormatter)
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
                            .tint(.orange)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .buttonStyle(BorderlessButtonStyle())
                            .controlSize(.mini)
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

        private var overrideLabelDivider: some View {
            Divider()
                .frame(width: 1, height: 20)
        }

        @ViewBuilder private func overridesView(for preset: OverrideStored) -> some View {
            let target = (state.units == .mgdL ? preset.target : preset.target?.decimalValue.asMmolL as NSDecimalNumber?) ?? 0

            let duration = (preset.duration ?? 0) as Decimal
            let name = ((preset.name ?? "") == "") || (preset.name?.isEmpty ?? true) ? "" : preset.name!
            let percent = preset.percentage / 100
            let perpetual = preset.indefinite
            let durationString = perpetual ? "" : "\(formatHrMin(Int(duration)))"
            let scheduledSMBstring = preset.smbIsScheduledOff && preset.start != preset.end
                ? " \(formatTimeRange(start: preset.start?.stringValue, end: preset.end?.stringValue))"
                : ""
            let smbString = (preset.smbIsOff || preset.smbIsScheduledOff) ? "SMBs Off\(scheduledSMBstring)" : ""
            let targetString = target != 0 ? "\(target.description) \(state.units.rawValue)" : ""
            let maxMinutesSMB = (preset.smbMinutes as Decimal?) != nil ? (preset.smbMinutes ?? 0) as Decimal : 0
            let maxMinutesUAM = (preset.uamMinutes as Decimal?) != nil ? (preset.uamMinutes ?? 0) as Decimal : 0
            let maxSmbMinsString = (maxMinutesSMB != 0 && preset.advancedSettings && maxMinutesSMB != state.defaultSmbMinutes) ?
                "\(maxMinutesSMB.formatted()) min SMB" : ""
            let maxUamMinsString = (maxMinutesUAM != 0 && preset.advancedSettings && maxMinutesUAM != state.defaultUamMinutes) ?
                "\(maxMinutesUAM.formatted()) min UAM" : ""
            let isfAndCRstring = (preset.isf == preset.cr) ? "" : (preset.isf ? " ISF" : " CR")
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
                                if durationString != "" {
                                    Text(durationString)
                                }
                                if percent != 1 {
                                    if durationString != "" {
                                        overrideLabelDivider
                                    }
                                    Text(
                                        "\(Int(percent * 100))%\(isfAndCRstring)"
                                    )
                                }
                                if targetString != "" {
                                    overrideLabelDivider
                                    Text(targetString)
                                }
                                if smbString != "" {
                                    overrideLabelDivider
                                    Text(smbString).foregroundColor(.secondary).font(.caption)
                                }
                                if maxSmbMinsString != "" {
                                    overrideLabelDivider
                                    Text(maxSmbMinsString)
                                }
                                if maxUamMinsString != "" {
                                    overrideLabelDivider
                                    Text(maxUamMinsString)
                                }
                                Spacer()
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
            }
        }
    }
}
