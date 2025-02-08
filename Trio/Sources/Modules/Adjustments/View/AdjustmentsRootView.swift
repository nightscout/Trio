import CoreData
import SwiftUI
import Swinject

extension Adjustments {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State var isEditing = false
        @State var showOverrideCreationSheet = false
        @State var showTempTargetCreationSheet = false
        @State var showingDetail = false
        @State var showOverrideCheckmark: Bool = false
        @State var showTempTargetCheckmark: Bool = false
        @State var selectedOverridePresetID: String?
        @State var selectedTempTargetPresetID: String?
        @State var selectedOverride: OverrideStored?
        @State var selectedTempTarget: TempTargetStored?
        @State var isConfirmDeletePresented = false
        @State var isPromptPresented = false
        @State var isRemoveAlertPresented = false
        @State var removeAlert: Alert?
        @State var isEditingTT = false

        private var shouldDisplayStickyOverrideStopButton: Bool {
            state.isOverrideEnabled && state.activeOverrideName.isNotEmpty
        }

        private var shouldDisplayStickyTempTargetStopButton: Bool {
            state.isTempTargetEnabled && state.activeTempTargetName.isNotEmpty
        }

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        func formattedGlucose(glucose: Decimal) -> String {
            let formattedValue: String
            if state.units == .mgdL {
                formattedValue = Formatter.glucoseFormatter(for: state.units)
                    .string(from: glucose as NSDecimalNumber) ?? "\(glucose)"
            } else {
                formattedValue = glucose.formattedAsMmolL
            }
            return "\(formattedValue) \(state.units.rawValue)"
        }

        var body: some View {
            ZStack(alignment: .center, content: {
                VStack {
                    Picker("Adjustment Tabs", selection: $state.selectedTab) {
                        ForEach(Adjustments.Tab.allCases.indexed(), id: \.1) { index, item in
                            Text(item.name).tag(index)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)

                    List {
                        switch state.selectedTab {
                        case .overrides: overrides()
                        case .tempTargets: tempTargets() }
                    }
                    .scrollContentBackground(.hidden)
                    .background(appState.trioBackgroundColor(for: colorScheme))
                }
                .listSectionSpacing(10)
                .safeAreaInset(
                    edge: .bottom,
                    spacing: shouldDisplayStickyOverrideStopButton || shouldDisplayStickyTempTargetStopButton ? 30 : 0
                ) {
                    if shouldDisplayStickyOverrideStopButton, state.selectedTab == .overrides {
                        stickyStopOverrideButton
                    } else if shouldDisplayStickyTempTargetStopButton, state.selectedTab == .tempTargets {
                        stickyStopTempTargetButton
                    } else {
                        EmptyView()
                    }
                }
                .scrollContentBackground(.hidden)
                .background(appState.trioBackgroundColor(for: colorScheme))
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
            }).background(appState.trioBackgroundColor(for: colorScheme))
        }

        var defaultText: some View {
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

        var currentActiveAdjustment: some View {
            switch state.selectedTab {
            case .overrides:
                Section {
                    HStack {
                        Text("\(state.activeOverrideName) is running")

                        Spacer()
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Color.primary)
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
                .listRowBackground(Color.purple.opacity(0.8))
            case .tempTargets:
                Section {
                    HStack {
                        Text("\(state.activeTempTargetName) is running")

                        Spacer()
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Color.primary)
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
                .listRowBackground(Color.loopGreen.opacity(0.8))
            }
        }

        var cancelAdjustmentButton: some View {
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
                    .disabled(!state.isOverrideEnabled)
                    .listRowBackground(!state.isOverrideEnabled ? Color(.systemGray4) : Color(.systemRed))
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

        func formattedTimeRemaining(_ timeInterval: TimeInterval) -> String {
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
    }
}
