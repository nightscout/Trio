import SwiftUI
import Swinject

extension TherapyProfiles {
    struct ProfileRootView: BaseView {
        let resolver: Resolver
        let profileName: String
        @State var state = StateModel()

        var body: some View {
            TherapyProfileDetailView(state: state, profileName: profileName)
                .onAppear(perform: configureView)
        }
    }
}

struct TherapyProfileDetailView: View {
    let state: TherapyProfiles.StateModel
    @State var profileName: String

    @State private var isConfirmingActivation = false
    @State private var isConfirmingDeletion = false
    @State private var isRenaming = false
    @State private var newName = ""

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    init(state: TherapyProfiles.StateModel, profileName: String) {
        self.state = state
        _profileName = State(initialValue: profileName)
    }

    private var profile: TrioTherapyProfile? { state.profile(named: profileName) }

    var body: some View {
        List {
            if let profile {
                Section {
                    if state.isActive(profile) {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                    } else {
                        Label("Not active", systemImage: "circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.chart)

                scheduleSection(
                    title: String(localized: "Basal Rates"),
                    editor: .basal,
                    rows: profile.basal.map {
                        ($0.seconds, $0.value.formatted() + " " + String(localized: "U/hr"))
                    }
                )
                scheduleSection(
                    title: String(localized: "Carb Ratios"),
                    editor: .carbRatio,
                    rows: profile.carbRatio.map {
                        ($0.seconds, $0.value.formatted() + " " + String(localized: "g/U"))
                    }
                )
                scheduleSection(
                    title: String(localized: "Insulin Sensitivities"),
                    editor: .sensitivity,
                    rows: profile.sensitivity.map {
                        (
                            $0.seconds,
                            $0.value.formattedISF(for: state.units) + " " + state.units.rawValue + "/" + String(localized: "U")
                        )
                    }
                )
                scheduleSection(
                    title: String(localized: "Glucose Targets"),
                    editor: .target,
                    rows: profile.target.map { ($0.seconds, $0.low.formatted(withUnits: state.units)) }
                )
                actionsSection(profile)
            }
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle(profileName)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if state.isBusy {
                ProgressView()
            }
        }
        .confirmationDialog("Activate \(profileName)?", isPresented: $isConfirmingActivation, titleVisibility: .visible) {
            Button("Activate") {
                state.activate(profileName)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let next = state.nextStart() {
                Text(
                    "Trio sends this profile's basal rates to the pump and starts using its carb ratios, insulin sensitivities and glucose targets right away."
                ) + Text(verbatim: " ") +
                    Text(
                        "\(profileName) stays active until \(next.profileName) starts \(TherapyProfiles.StateModel.startText(next))."
                    )
            } else {
                Text(
                    "Trio sends this profile's basal rates to the pump and starts using its carb ratios, insulin sensitivities and glucose targets right away."
                )
            }
        }
        .confirmationDialog("Delete \(profileName)?", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                state.delete(profileName) { deleted in
                    if deleted { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let count = state.scheduledSwitchCount(for: profileName)
            if count == 1 {
                Text("\(profileName) is used by 1 scheduled switch, which will be removed.") + Text(verbatim: " ") +
                    Text("At those times the profile active before stays active until the next scheduled start.")
            } else if count > 1 {
                Text("\(profileName) is used by \(count) scheduled switches, which will be removed.") + Text(verbatim: " ") +
                    Text("At those times the profile active before stays active until the next scheduled start.")
            }
        }
        .alert("Rename Profile", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let target = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                state.rename(profileName, to: target) { renamed in
                    if renamed { profileName = target }
                }
            }
            .disabled(state.nameProblem(newName, renaming: profileName) != nil)
        } message: {
            Text(state.nameProblem(newName, renaming: profileName) ?? String(localized: "Enter a new name for the profile."))
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

    private func scheduleSection(
        title: String,
        editor: TherapyProfiles.Editor,
        rows: [(seconds: Int, value: String)]
    ) -> some View {
        Section(header: Text(title)) {
            ForEach(rows, id: \.seconds) { row in
                HStack {
                    Text(TherapyProfileValidator.timeString(row.seconds))
                    Spacer()
                    Text(row.value).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            NavigationLink(value: Screen.therapyProfileEditor(editor, profileName: profileName)) {
                Text("Edit")
            }
            .accessibilityLabel(Text("Edit \(title)"))
            .disabled(state.isBusy)
        }
        .listRowBackground(Color.chart)
    }

    private func actionsSection(_ profile: TrioTherapyProfile) -> some View {
        Section {
            if !state.isActive(profile) {
                Button("Activate Profile") {
                    isConfirmingActivation = true
                }
                .disabled(state.isBusy)
            }
            if !profile.isDefault {
                Button("Rename Profile") {
                    newName = profileName
                    isRenaming = true
                }
                .disabled(state.isBusy)
            }
            if !profile.isDefault, !state.isActive(profile) {
                Button("Delete Profile", role: .destructive) {
                    isConfirmingDeletion = true
                }
                .disabled(state.isBusy)
            }
        }
        .listRowBackground(Color.chart)
    }
}
