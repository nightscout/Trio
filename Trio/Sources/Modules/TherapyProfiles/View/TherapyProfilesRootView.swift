import SwiftUI
import Swinject

extension TherapyProfiles {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()

        @State private var isNamingNewProfile = false
        @State private var newProfileName = ""
        @State private var shouldDisplayHint = false
        @State private var hintDetent = PresentationDetent.large
        @State private var editedSwitch: EditedSwitch?

        private struct EditedSwitch: Identifiable {
            let entry: ScheduledProfileSwitch
            let isNew: Bool
            var id: String { entry.id }
        }

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                Section(header: Text("Profiles")) {
                    ForEach(state.profiles) { profile in
                        NavigationLink(value: Screen.therapyProfileDetail(profile.name)) {
                            HStack {
                                Text(profile.name)
                                Spacer()
                                if state.isActive(profile) {
                                    Text("Active").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .listRowBackground(Color.chart)

                scheduledSwitchesSection

                Section {
                    Button("Save Current Settings as New Profile") {
                        newProfileName = ""
                        isNamingNewProfile = true
                    }
                    .disabled(state.isBusy)

                    HStack(alignment: .center) {
                        Text("Trio always uses the active profile.")
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(
                            action: { shouldDisplayHint.toggle() },
                            label: { Image(systemName: "questionmark.circle") }
                        )
                        .buttonStyle(BorderlessButtonStyle())
                        .accessibilityLabel(Text("Help"))
                    }
                }
                .listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Therapy Profiles")
            .navigationBarTitleDisplayMode(.automatic)
            .onAppear(perform: configureView)
            .overlay {
                if state.isBusy {
                    ProgressView()
                }
            }
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: String(localized: "Therapy Profiles"),
                    hintText: AnyView(
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "A profile holds basal rates, carb ratios, insulin sensitivities and glucose targets. Trio always uses the active profile, and editing the therapy settings edits the active profile."
                            )
                            Text(
                                "Activating a profile sends its basal rates to the pump first. Only when the pump accepts them does Trio start using the profile's carb ratios, insulin sensitivities and glucose targets."
                            )
                            Text(
                                "Overrides and temporary targets are not part of a profile. One that is running stays on and applies on top of the newly active profile."
                            )
                            Text(
                                "Trio switches the active profile at the scheduled starts. A profile stays active until the next scheduled start, also after a switch you make yourself. A paused start does not run until you resume it."
                            )
                        }
                    ),
                    sheetTitle: String(localized: "Help")
                )
            }
            .sheet(item: $editedSwitch) { edited in
                ScheduledSwitchEditorView(state: state, entry: edited.entry, isNew: edited.isNew)
            }
            .alert("New Profile", isPresented: $isNamingNewProfile) {
                TextField("Name", text: $newProfileName)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    state.saveActiveProfileAsNew(named: newProfileName)
                }
                .disabled(state.nameProblem(newProfileName) != nil)
            } message: {
                Text(state.nameProblem(newProfileName) ?? String(localized: "Enter a name for the new profile."))
            }
            .alert(
                "Profile Not Changed",
                isPresented: Binding(
                    get: { state.errorMessage != nil },
                    set: { if !$0 { state.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(state.errorMessage ?? "")
            }
        }

        private var scheduledSwitchesSection: some View {
            Section {
                ForEach(state.scheduledSwitches) { entry in
                    Button {
                        editedSwitch = EditedSwitch(entry: entry, isNew: false)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(TherapyProfiles.StateModel.shortStartText(entry)) · \(entry.profileName) starts")
                                .foregroundStyle(entry.paused ? Color.secondary : Color.primary)
                            if entry.paused {
                                Text("Paused").font(.footnote).foregroundStyle(.secondary)
                            } else if let next = state.nextStart(after: entry) {
                                Text("until \(TherapyProfiles.StateModel.shortStartText(next))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            state.deleteScheduledSwitch(entry.id)
                        }
                        Button(entry.paused ? String(localized: "Resume") : String(localized: "Pause")) {
                            state.setPaused(!entry.paused, for: entry.id)
                        }
                    }
                    .disabled(state.isBusy)
                }
                Button("Add Scheduled Switch") {
                    editedSwitch = EditedSwitch(
                        entry: ScheduledProfileSwitch(profileName: state.activeProfileName, weekday: 2, time: 7 * 3600),
                        isNew: true
                    )
                }
                .disabled(state.isBusy || state.scheduledSwitches.count >= ScheduledProfileSwitch.maxCount)
            } header: {
                Text("Scheduled Switches")
            } footer: {
                Text(scheduledSwitchesFooter)
            }
            .listRowBackground(Color.chart)
        }

        private var scheduledSwitchesFooter: String {
            guard !state.scheduledSwitches.isEmpty else {
                return String(localized: "No scheduled switches. Trio keeps the active profile until you switch.")
            }
            guard let next = state.nextStart() else {
                return String(localized: "All starts are paused.")
            }
            let paused = state.scheduledSwitches.filter(\.paused).count
            let nextText = String(
                localized: "Next: \(next.profileName) starts \(TherapyProfiles.StateModel.startText(next))."
            )
            return paused == 0 ? nextText : nextText + " " + String(localized: "\(paused) starts paused.")
        }
    }
}
