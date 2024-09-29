import CoreData
import SwiftUI
import Swinject

extension OverrideConfig {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()

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

        var body: some View {
            VStack {
                HStack(spacing: 6) {
                    HStack {
                        Spacer()
                        Image(systemName: "clock.arrow.2.circlepath")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.primary, Color(red: 0.62, green: 0.42, blue: 0.98))
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
                            showTempTargetCreationSheet = false
                            await state.resetStateVariables()
                        }
                    }) {
                        AddTempTargetForm(state: state)
                    }
                    .sheet(isPresented: $state.showTempTargetEditSheet, onDismiss: {
                        Task {
                            state.showTempTargetEditSheet = false
                            await state.resetTempTargetState()
                        }

                    }) {
                        if let tempTarget = selectedTempTarget {
                            EditTempTargetForm(tempTargetToEdit: tempTarget, state: state)
                        }
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
                currentActiveAdjustment
            }

            if state.overridePresets.isNotEmpty || state.currentActiveOverride != nil {
                cancelAdjustmentButton
            }
        }

        @ViewBuilder func tempTargets() -> some View {
            if state.tempTargetPresets.isNotEmpty {
                tempTargetPresets
            } else {
                defaultText
            }

            if state.isTempTargetEnabled, state.activeTempTargetName.isNotEmpty {
                currentActiveAdjustment
            }

            if state.tempTargetPresets.isNotEmpty || state.currentActiveTempTarget != nil {
                cancelAdjustmentButton
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
                }
            }
        }

        private var tempTargetPresets: some View {
            Section {
                ForEach(state.tempTargetPresets) { preset in
                    tempTargetView(for: preset)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .none) {
                                Task {
                                    await state.invokeTempTargetPresetDeletion(preset.objectID)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .tint(.red)
                            }
                            Button(action: {
                                // Set the selected Temp Target to the chosen Preset and pass it to the Edit Sheet
                                selectedTempTarget = preset
                                state.showTempTargetEditSheet = true
                            }, label: {
                                Label("Edit", systemImage: "pencil")
                                    .tint(.blue)
                            })
                        }
                }
//                .onMove(perform: state.reorderOverride)
                .listRowBackground(Color.chart)
            } header: {
                Text("Presets")
            } footer: {
                HStack {
                    Image(systemName: "hand.draw.fill")
                    Text("Swipe left to edit or delete an Temp Target preset. Hold, drag and drop to reorder a preset.")
                }
            }
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
                    Text("Cancel Override")

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
                    }
                }, label: {
                    Text("Cancel Temp Target")

                })
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(!state.isTempTargetEnabled)
                    .listRowBackground(!state.isTempTargetEnabled ? Color(.systemGray4) : Color(.systemRed))
                    .tint(.white)
            }
        }

        private func tempTargetView(for preset: TempTargetStored) -> some View {
            var target = preset.target
//            if state.units == .mmolL {
//                target.asMmolL
//            }
            let isSelected = preset.id?.uuidString == selectedTempTargetPresetID

            return ZStack(alignment: .trailing, content: {
                HStack {
                    VStack {
                        HStack {
                            Text(preset.name ?? "")
                            Spacer()
                        }
                        HStack(spacing: 2) {
                            Text(
                                "\(formatter.string(from: (target ?? 0) as NSNumber)!)"
                            )
                            .foregroundColor(.secondary)
                            .font(.caption)

                            Text(state.units.rawValue)
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("for")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("\(formatter.string(from: (preset.duration ?? 0) as NSNumber)!)")
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
            let target = (state.units == .mgdL ? preset.target : preset.target?.decimalValue.asMmolL as NSDecimalNumber?) ?? 0

            let duration = (preset.duration ?? 0) as Decimal
            let name = ((preset.name ?? "") == "") || (preset.name?.isEmpty ?? true) ? "" : preset.name!
            let percent = preset.percentage / 100
            let perpetual = preset.indefinite
            let durationString = perpetual ? "" : "\(formatter.string(from: duration as NSNumber)!)"
            let scheduledSMBstring = (preset.smbIsOff && preset.smbIsAlwaysOff) ? "Scheduled SMBs" : ""
            let smbString = (preset.smbIsOff && scheduledSMBstring == "") ? "SMBs are off" : ""
            let targetString = target != 0 ? target.description : ""
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
