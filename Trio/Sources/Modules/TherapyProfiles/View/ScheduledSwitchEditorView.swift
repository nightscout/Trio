import SwiftUI

struct ScheduledSwitchEditorView: View {
    let state: TherapyProfiles.StateModel
    let isNew: Bool
    @State private var entry: ScheduledProfileSwitch
    @State private var time: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    init(state: TherapyProfiles.StateModel, entry: ScheduledProfileSwitch, isNew: Bool) {
        self.state = state
        self.isNew = isNew
        _entry = State(initialValue: entry)
        _time = State(
            initialValue: Calendar.current.date(
                bySettingHour: entry.time / 3600,
                minute: entry.time % 3600 / 60,
                second: 0,
                of: Date()
            ) ?? Date()
        )
    }

    /// Monday first.
    private var weekdays: [Int] { [2, 3, 4, 5, 6, 7, 1] }

    private var problem: String? { state.scheduledSwitchProblem(entry) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Profile", selection: $entry.profileName) {
                        ForEach(state.profiles) { profile in
                            Text(profile.name).tag(profile.name)
                        }
                    }
                    Picker("Weekday", selection: $entry.weekday) {
                        ForEach(weekdays, id: \.self) { weekday in
                            Text(TherapyProfileValidator.weekdayName(weekday)).tag(weekday)
                        }
                    }
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .onChange(of: time) { _, newTime in
                            let components = Calendar.current.dateComponents([.hour, .minute], from: newTime)
                            entry.time = (components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60
                        }
                } footer: {
                    Text(
                        problem ?? String(
                            localized: "\(entry.profileName) starts every \(TherapyProfiles.StateModel.startText(entry)) and stays active until the next scheduled start."
                        )
                    )
                    .foregroundStyle(problem == nil ? Color.secondary : Color.red)
                }
                .listRowBackground(Color.chart)

                Section {
                    Toggle("Paused", isOn: $entry.paused)
                } footer: {
                    Text(
                        "A paused start does not run until you resume it. Nothing is switched when you resume; the start runs again at its next time."
                    )
                }
                .listRowBackground(Color.chart)

                if !isNew {
                    Section {
                        Button("Delete Scheduled Switch", role: .destructive) {
                            state.deleteScheduledSwitch(entry.id) { deleted in
                                if deleted { dismiss() }
                            }
                        }
                        .disabled(state.isBusy)
                    }
                    .listRowBackground(Color.chart)
                }
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle(isNew ? String(localized: "Add Scheduled Switch") : String(localized: "Scheduled Switch"))
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                "Scheduled Switches Not Changed",
                isPresented: Binding(
                    get: { state.errorMessage != nil },
                    set: { if !$0 { state.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(state.errorMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        state.saveScheduledSwitch(entry) { saved in
                            if saved { dismiss() }
                        }
                    }
                    .disabled(problem != nil || state.isBusy)
                }
            }
        }
    }
}
