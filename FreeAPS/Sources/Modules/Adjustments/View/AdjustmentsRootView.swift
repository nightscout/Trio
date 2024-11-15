import CoreData
import SwiftUI
import Swinject

extension OverrideConfig {
    struct RootView: BaseView {
        let resolver: Resolver

        @State var state = StateModel()

        @State private var isEditing = false
        @State private var showOverrideCreationSheet = false
        @State private var showTempTargetCreationSheet = false
        @State private var showingDetail = false
        @State private var showCheckmark: Bool = false
        @State private var selectedPresetID: String?
        @State private var selectedTempTargetPresetID: String?
        @State private var selectedOverride: OverrideStored?
        @State private var selectedTempTarget: TempTargetStored?

        // temp targets
        @State private var isConfirmDeletePresented = false
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

        private func formattedGlucose(glucose: Decimal) -> String {
            let formattedValue: String
            if state.units == .mgdL {
                formattedValue = glucoseFormatter.string(from: glucose as NSDecimalNumber) ?? "\(glucose)"
            } else {
                formattedValue = glucose.formattedAsMmolL
            }
            return "\(formattedValue) \(state.units.rawValue)"
        }

        var body: some View {
            VStack {
                HStack(spacing: 6) {
                    HStack {
                        Spacer()
                        Image(systemName: "clock.arrow.2.circlepath")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.primary, Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569))
                        Text(OverrideConfig.Tab.overrides.name)
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .background(state.selectedTab == .overrides ? Color.loopGray.opacity(0.4) : Color.clear)
                    .cornerRadius(8)
                    .onTapGesture {
                        withAnimation {
                            state.selectedTab = .overrides
                        }
                    }
                    HStack {
                        Spacer()
                        Image(systemName: "target")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.loopGreen)
                        Text(OverrideConfig.Tab.tempTargets.name)
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .background(state.selectedTab == .tempTargets ? Color.loopGray.opacity(0.4) : Color.clear)
                    .cornerRadius(8)
                    .onTapGesture {
                        withAnimation {
                            state.selectedTab = .tempTargets
                        }
                    }
                }
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .padding(.horizontal)

                List {
                    switch state.selectedTab {
                    case .overrides: overrides()
                    case .tempTargets: tempTargets() }
                }
                .listSectionSpacing(10)
                .safeAreaInset(edge: .bottom, spacing: 30) { stickyStopButton }
                .scrollContentBackground(.hidden).background(color)
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
                        case .tempTargets:
                            Button(action: {
                                showTempTargetCreationSheet = true
                            }, label: {
                                HStack {
                                    Text("Add Temp Target")
                                    Image(systemName: "plus")
                                }
                            })
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
                .sheet(isPresented: $showTempTargetCreationSheet, onDismiss: {
                    Task {
                        await state.resetTempTargetState()
                        showTempTargetCreationSheet = false
                    }
                }) {
                    AddTempTargetForm(state: state)
                }
                .sheet(isPresented: $state.showTempTargetEditSheet, onDismiss: {
                    Task {
                        await state.resetTempTargetState()
                        state.showTempTargetEditSheet = false
                    }

                }) {
                    if let tempTarget = selectedTempTarget {
                        EditTempTargetForm(tempTargetToEdit: tempTarget, state: state)
                    }
                }
            }.background(color)
        }

        @ViewBuilder func overrides() -> some View {
            if state.isEnabled, state.activeOverrideName.isNotEmpty {
                currentActiveAdjustment
            }
            if state.overridePresets.isNotEmpty {
                overridePresets
            } else {
                defaultText
            }
        }

        @ViewBuilder func tempTargets() -> some View {
            if state.isTempTargetEnabled, state.activeTempTargetName.isNotEmpty {
                currentActiveAdjustment
            }
            if state.scheduledTempTargets.isNotEmpty {
                scheduledTempTargets
            }
            if state.tempTargetPresets.isNotEmpty {
                tempTargetPresets
            } else {
                defaultText
            }
        }

        private var defaultText: some View {
            switch state.selectedTab {
            case .overrides:
                Section {} header: {
                    Text("Add Preset or Override by tapping 'Add Override +' in the top right-hand corner of the screen.")
                        .textCase(nil)
                        .foregroundStyle(.secondary)
                }
            case .tempTargets:
                Section {} header: {
                    Text(
                        "Add Preset or Temp Target by tapping 'Add Temp Target +' in the top right-hand corner of the screen."
                    )
                    .textCase(nil)
                    .foregroundStyle(.secondary)
                }
            }
        }

        private var overridePresets: some View {
            Section {
                ForEach(state.overridePresets) { preset in
                    overridesView(for: preset)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .none) {
                                selectedOverride = preset
                                isConfirmDeletePresented = true
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
                    isPresented: $isConfirmDeletePresented,
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

        private var scheduledTempTargets: some View {
            Section {
                ForEach(state.scheduledTempTargets) { tempTarget in
                    tempTargetView(for: tempTarget)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            swipeActions(for: tempTarget)
                        }
                }
                .listRowBackground(Color.chart)
            } header: {
                Text("Scheduled Temp Targets")
            }
        }

        private var tempTargetPresets: some View {
            Section {
                ForEach(state.tempTargetPresets) { preset in
                    tempTargetView(for: preset, showCheckmark: showCheckmark) {
                        enactTempTargetPreset(preset)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        swipeActions(for: preset)
                    }
                }
                .onMove(perform: state.reorderTempTargets)
                .confirmationDialog(
                    deleteConfirmationTitle,
                    isPresented: $isConfirmDeletePresented,
                    titleVisibility: .visible
                ) {
                    deleteConfirmationButtons()
                } message: {
                    deleteConfirmationMessage
                }
                .listRowBackground(Color.chart)
            } header: {
                Text("Presets")
            } footer: {
                HStack {
                    Image(systemName: "hand.draw.fill")
                    Text("Swipe left to edit or delete a Temp Target preset. Hold, drag and drop to reorder a preset.")
                }
            }
        }

        private func enactTempTargetPreset(_ preset: TempTargetStored) {
            Task {
                let objectID = preset.objectID
                await state.enactTempTargetPreset(withID: objectID)
                selectedTempTargetPresetID = preset.id?.uuidString
                showCheckmark.toggle()

                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showCheckmark = false
                }
            }
        }

        private func swipeActions(for tempTarget: TempTargetStored) -> some View {
            Group {
                Button {
                    Task {
                        selectedTempTarget = tempTarget
                        isConfirmDeletePresented = true
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                        .tint(.red)
                }
                Button(action: {
                    selectedTempTarget = tempTarget
                    state.showTempTargetEditSheet = true
                }, label: {
                    Label("Edit", systemImage: "pencil")
                        .tint(.blue)
                })
            }
        }

        private var deleteConfirmationTitle: String {
            "Delete the Temp Target Preset \"\(selectedTempTarget?.name ?? "")\"?"
        }

        private func deleteConfirmationButtons() -> some View {
            Group {
                if let itemToDelete = selectedTempTarget {
                    Button(
                        state.currentActiveTempTarget == selectedTempTarget ? "Stop and Delete" : "Delete",
                        role: .destructive
                    ) {
                        if state.currentActiveTempTarget == selectedTempTarget {
                            Task {
                                await state.disableAllActiveTempTargets(createTempTargetRunEntry: true)
                            }
                        }
                        Task {
                            await state.invokeTempTargetPresetDeletion(itemToDelete.objectID)
                        }
                        selectedTempTarget = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    selectedTempTarget = nil
                }
            }
        }

        private var deleteConfirmationMessage: Text? {
            if state.currentActiveTempTarget == selectedTempTarget {
                return Text("This Temp Target preset is currently running. Deleting will stop it.")
            }
            return nil
        }

        private var currentActiveAdjustment: some View {
            switch state.selectedTab {
            case .overrides:
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
            case .tempTargets:
                Section {
                    HStack {
                        Text("\(state.activeTempTargetName) is running")

                        Spacer()
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Color.blue)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task {
                            /// To avoid editing the Preset when a Preset-Override is running we first duplicate the Preset-Override as a non-Preset Override
                            /// The currentActiveOverride variable in the State will update automatically via MOC notification
                            await state.duplicateTempTargetPresetAndCancelPreviousTempTarget()

                            /// selectedOverride is used for passing the chosen Override to the EditSheet so we have to set the updated currentActiveOverride to be the selectedOverride
                            selectedTempTarget = state.currentActiveTempTarget

                            /// Now we can show the Edit sheet
                            state.showTempTargetEditSheet = true
                        }
                    }
                }
                .listRowBackground(Color.blue.opacity(0.2))
            }
        }

        var stickyStopButton: some View {
            ZStack {
                Rectangle()
                    .frame(width: UIScreen.main.bounds.width, height: 65)
                    .foregroundStyle(colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white)
                    .background(.thinMaterial)
                    .opacity(0.8)
                    .clipShape(Rectangle())
                Group {
                    switch state.selectedTab {
                    case .overrides:
                        Button(action: {
                            Task {
                                // Save cancelled Override in OverrideRunStored Entity
                                // Cancel ALL active Override
                                await state.disableAllActiveOverrides(createOverrideRunEntry: true)
                            }
                        }, label: {
                            Text("Stop Override")
                                .padding(10)
                        })
                            .frame(width: UIScreen.main.bounds.width * 0.9, alignment: .center)
                            .disabled(!state.isEnabled)
                            .background(!state.isEnabled ? Color(.systemGray4) : Color(.systemRed))
                            .tint(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .tempTargets:
                        Button(action: {
                            Task {
                                // Save cancelled Temp Targets in TempTargetRunStored Entity
                                // Cancel ALL active Temp Targets
                                await state.disableAllActiveTempTargets(createTempTargetRunEntry: true)
                                // Update View
                                state.updateLatestTempTargetConfiguration()
                            }
                        }, label: {
                            Text("Stop Temp Target")
                                .padding(10)
                        })
                            .frame(width: UIScreen.main.bounds.width * 0.9, alignment: .center)
                            .disabled(!state.isTempTargetEnabled)
                            .background(!state.isTempTargetEnabled ? Color(.systemGray4) : Color(.systemRed))
                            .tint(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(5)
            }
        }

        private var cancelAdjustmentButton: some View {
            switch state.selectedTab {
            case .overrides:
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
            case .tempTargets:
                Button(action: {
                    Task {
                        // Save cancelled Temp Targets in TempTargetRunStored Entity
                        // Cancel ALL active Temp Targets
                        await state.disableAllActiveTempTargets(createTempTargetRunEntry: true)

                        // Update View
                        state.updateLatestTempTargetConfiguration()
                    }
                }, label: {
                    Text("Stop Temp Target")

                })
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(!state.isTempTargetEnabled)
                    .listRowBackground(!state.isTempTargetEnabled ? Color(.systemGray4) : Color(.systemRed))
                    .tint(.white)
            }
        }

        private func tempTargetView(
            for tempTarget: TempTargetStored,
            showCheckmark: Bool = false,
            onTap: (() -> Void)? = nil
        ) -> some View {
            let target = tempTarget.target ?? 100
            let tempTargetValue = Decimal(target as! Double.RawValue)
            let isSelected = tempTarget.id?.uuidString == selectedPresetID
            let tempTargetHalfBasal = Decimal(
                tempTarget.halfBasalTarget as? Double
                    .RawValue ?? Double(state.settingHalfBasalTarget)
            )
            let percentage = Int(
                state.computeAdjustedPercentage(usingHBT: tempTargetHalfBasal, usingTarget: tempTargetValue)
            )
            let remainingTime = tempTarget.date?.timeIntervalSinceNow ?? 0

            return ZStack(alignment: .trailing) {
                HStack {
                    VStack(alignment: .leading) {
                        HStack {
                            Text(tempTarget.name ?? "")
                            Spacer()
                            if remainingTime > 0 {
                                Text("Starts in \(formattedTimeRemaining(remainingTime))")
                                    .foregroundColor(colorScheme == .dark ? .orange : .accentColor)
                            }
                        }
                        HStack(spacing: 2) {
                            Text(formattedGlucose(glucose: target as Decimal))
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("for")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("\(formatter.string(from: (tempTarget.duration ?? 0) as NSNumber)!)")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("min")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            if state.isAdjustSensEnabled(usingTarget: tempTargetValue) {
                                Text(", \(percentage)%")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTap?()
                    }
                }
                if showCheckmark && isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .imageScale(.large)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.green)
                } else if onTap != nil {
                    Image(systemName: "line.3.horizontal")
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                }
            }
        }

        private func formattedTimeRemaining(_ timeInterval: TimeInterval) -> String {
            let totalSeconds = Int(timeInterval)
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60

            if hours > 0 {
                return "\(hours)h \(minutes)m \(seconds)s"
            } else if minutes > 0 {
                return "\(minutes)m \(seconds)s"
            } else {
                return "<1m"
            }
        }

        private var overrideLabelDivider: some View {
            Divider()
                .frame(width: 1, height: 20)
        }

        @ViewBuilder private func overridesView(for preset: OverrideStored) -> some View {
            let isSelected = preset.id == selectedPresetID
            let name = preset.name ?? ""
            let indefinite = preset.indefinite
            let duration = preset.duration?.decimalValue ?? Decimal(0)
            let percentage = preset.percentage
            let smbMinutes = preset.smbMinutes?.decimalValue ?? Decimal(0)
            let uamMinutes = preset.uamMinutes?.decimalValue ?? Decimal(0)

            let target: String = {
                guard let targetValue = preset.target, targetValue != 0 else { return "" }
                return state.units == .mgdL ? targetValue.description : targetValue.decimalValue.formattedAsMmolL
            }()

            let targetString = target.isEmpty ? "" : "\(target) \(state.units.rawValue)"

            let durationString = indefinite ? "" : "\(formatHrMin(Int(duration)))"

            let scheduledSMBString: String = {
                guard preset.smbIsScheduledOff, preset.start != preset.end else { return "" }
                return " \(formatTimeRange(start: preset.start?.stringValue, end: preset.end?.stringValue))"
            }()

            let smbString: String = {
                guard preset.smbIsOff || preset.smbIsScheduledOff else { return "" }
                return "SMBs Off\(scheduledSMBString)"
            }()

            let maxSmbMinsString: String = {
                guard smbMinutes != 0, preset.advancedSettings, !preset.smbIsOff,
                      smbMinutes != state.defaultSmbMinutes else { return "" }
                return "\(smbMinutes.formatted()) min SMB"
            }()

            let maxUamMinsString: String = {
                guard uamMinutes != 0, preset.advancedSettings, !preset.smbIsOff,
                      uamMinutes != state.defaultUamMinutes else { return "" }
                return "\(uamMinutes.formatted()) min UAM"
            }()

            let isfAndCrString: String = {
                switch (preset.isfAndCr, preset.isf, preset.cr) {
                case (_, true, true),
                     (true, _, _):
                    return " ISF/CR"
                case (false, true, false):
                    return " ISF"
                case (false, false, true):
                    return " CR"
                default:
                    return ""
                }
            }()

            let percentageString = percentage != 100 ? "\(Int(percentage))%\(isfAndCrString)" : ""

            // Combine all labels into a single array, filtering out empty strings
            let labels: [String] = [
                durationString,
                percentageString,
                targetString,
                smbString,
                maxSmbMinsString,
                maxUamMinsString
            ].filter { !$0.isEmpty }

            if !name.isEmpty {
                ZStack(alignment: .trailing) {
                    HStack {
                        VStack {
                            HStack {
                                Text(name)
                                Spacer()
                            }
                            HStack(spacing: 5) {
                                ForEach(labels, id: \.self) { label in
                                    Text(label)
                                    if label != labels.last { // Add divider between labels
                                        overrideLabelDivider
                                    }
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

                                // Deactivate checkmark after 3 seconds
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
                }
            }
        }
    }
}
