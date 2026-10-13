import SwiftUI

struct TrioCloudBackupConfigurationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @State private var automatic = true
    @State private var manualRetention = 15
    @State private var automaticRetention = 15
    @State private var updatingRetention = false
    @State private var pending = 0
    @State private var error: String?
    @State private var decimalPlaceholder: Decimal = 0
    @State private var shouldDisplayHint = false
    @State private var hintDetent = PresentationDetent.large
    @State private var selectedVerboseHint: AnyView?
    @State private var hintLabel = ""

    private let automaticDescription = String(
        localized: "Once a day, Trio will check for any new settings changes and automatically back them up."
    )
    private let retentionDescription = String(
        localized: "Choose the maximum number of backups to keep in iCloud. When this limit is reached, Trio will automatically delete the oldest backup to make room for a new one."
    )

    var body: some View {
        List {
            SettingInputSection(
                decimalValue: $decimalPlaceholder,
                booleanValue: $automatic,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = String(localized: "Automatic Backup")
                    }
                ),
                units: .mgdL,
                type: .boolean,
                label: automatic ? String(localized: "Enabled") : String(localized: "Disabled"),
                miniHint: automaticDescription,
                verboseHint: VStack(alignment: .leading, spacing: 10) {
                    Text(automaticDescription)
                    Text("Checks run while Trio is running or the next time you open it. Unchanged settings do not create another backup.")
                    Text("Dynamic ISF history is included in backups, but new history alone does not trigger a backup.")
                },
                headerText: String(localized: "Automatic Backup")
            ).listRowBackground(Color.chart)
            Section("Backup Retention") {
                retentionRow
            }.listRowBackground(Color.chart)
            if pending > 0 { Text("\(pending) backup operation(s) pending.").listRowBackground(Color.chart) }
            if let error { Text(error).foregroundStyle(.secondary).listRowBackground(Color.chart) }
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .listSectionSpacing(sectionSpacing)
        .navigationTitle("Configuration")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: automatic) { _, value in TrioCloudBackupCoordinator.shared.automaticEnabled = value }
        .sheet(isPresented: $shouldDisplayHint) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint,
                hintLabel: hintLabel,
                hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
        .onAppear {
            let coordinator = TrioCloudBackupCoordinator.shared
            automatic = coordinator.automaticEnabled
            manualRetention = coordinator.retentionLimit(for: .manual)
            automaticRetention = coordinator.retentionLimit(for: .automatic)
            do { pending = try coordinator.pendingOperationCount() }
            catch { self.error = error.localizedDescription }
            if error == nil {
                error = coordinator.lastRetentionError
                    .map { _ in "Some older backups couldn’t be removed. Trio will retry when you reopen the app." }
                    ?? coordinator.lastError?.localizedDescription
            }
        }
    }

    private var retentionRow: some View {
        VStack {
            retentionPicker("Manual Backup", selection: $manualRetention, origin: .manual)
            retentionPicker("Automatic Backup", selection: $automaticRetention, origin: .automatic).padding(.top)
            HStack(alignment: .center) {
                Text(retentionDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    hintLabel = String(localized: "Backup Retention")
                    selectedVerboseHint = AnyView(Text(retentionDescription))
                    shouldDisplayHint = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("More information about Backup Retention")
            }.padding(.top)
        }.padding(.vertical)
    }

    private func retentionPicker(_ title: LocalizedStringKey, selection: Binding<Int>, origin: TrioSettingsBackup.Origin) -> some View {
        Picker(title, selection: selection) {
            ForEach(TrioCloudBackupCoordinator.retentionChoices, id: \.self) { count in Text("\(count)").tag(count) }
        }
        .pickerStyle(.menu)
        .disabled(updatingRetention)
        .onChange(of: selection.wrappedValue) { _, limit in
            let coordinator = TrioCloudBackupCoordinator.shared
            guard coordinator.retentionLimit(for: origin) != limit else { return }
            updatingRetention = true
            Task { @MainActor in
                defer { updatingRetention = false }
                do {
                    try await coordinator.setRetentionLimit(limit, for: origin)
                    error = nil
                } catch {
                    selection.wrappedValue = coordinator.retentionLimit(for: origin)
                    self.error = coordinator.retentionLimit(for: origin) == limit && coordinator.lastRetentionError != nil
                        ? "Your limit is saved. Older backups will be removed when iCloud is available."
                        : error.localizedDescription
                }
            }
        }
    }
}
