import SwiftUI

struct TrioCloudBackupDetailView: View {
    let entry: TrioCloudBackupEntry
    let onSelectForOnboarding: ((TrioSettingsBackup) -> Void)?
    let allowsExport: Bool
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var backup: TrioSettingsBackup?
    @State private var loading = true
    @State private var message: String?
    @State private var showingRestoreConfirmation = false
    @State private var restoring = false
    @State private var restored = false
    @State private var exported: TrioCloudBackupFile?

    init(
        entry: TrioCloudBackupEntry,
        snapshot: TrioSettingsBackup? = nil,
        allowsExport: Bool = true,
        onSelectForOnboarding: ((TrioSettingsBackup) -> Void)?
    ) {
        self.entry = entry
        self.onSelectForOnboarding = onSelectForOnboarding
        self.allowsExport = allowsExport
        _backup = State(initialValue: snapshot)
    }

    var body: some View {
        ZStack {
            backupList
        }
        .sheet(item: $exported) { file in
            ShareSheet(activityItems: [file.url])
        }
    }

    private var backupList: some View {
        List {
            Section("Info") {
                LabeledContent("Name", value: entry.name ?? (entry.origin == .manual ? "Manual Backup" : "Automatic Backup"))
                LabeledContent("Created", value: entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("App Version", value: backup?.appVersion ?? entry.appVersion ?? "—")
            }.listRowBackground(Color.chart)
            if let backup {
                let nodes = BackupSettingsNode.make(from: backup)
                Section("Contents") {
                    ForEach(nodes) { node in
                        NavigationLink {
                            BackupSettingsPreviewView(node: node)
                        } label: { Text(LocalizedStringKey(node.title)) }
                    }
                }.listRowBackground(Color.chart)
                Section {
                    VStack {
                        restoreButton
                        if allowsExport && onSelectForOnboarding == nil { exportButton }
                    }
                    .padding(.top, 12)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }.listRowBackground(Color.clear)
            } else {
                Section {
                    if loading { ProgressView("Loading backup…") }
                    else { Text("This backup couldn’t be opened.").foregroundStyle(.secondary) }
                }.listRowBackground(Color.chart)
            }
        }
        .disabled(restoring)
        .listSectionSpacing(sectionSpacing)
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Backup Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .tint(.primary).accessibilityLabel("Close backup details").disabled(restoring)
            }
        }
        .task {
            defer { loading = false }
            do {
                if backup == nil { backup = try await TrioCloudBackupCoordinator.shared.downloadBackup(id: entry.id) }
            } catch { message = error.localizedDescription }
        }
        .alert("Backup & Restore", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("Done", role: .cancel) {}
        } message: { Text(message ?? "") }
        .alert("Settings Restored!", isPresented: $restored) {
            Button("Continue") { dismiss() }
        } message: {
            Text(
                "Settings restored in Open Loop. Your pump must be unpaired before restoring; review therapy settings before reconnecting it."
            )
        }
        .overlay {
            if restoring {
                ZStack {
                    appState.trioBackgroundColor(for: colorScheme).ignoresSafeArea()
                    ProgressView("Restoring settings… Keep Trio open.")
                }
            }
        }
        .interactiveDismissDisabled(restoring)
    }

    private var restoreButton: some View {
        Group {
            if onSelectForOnboarding == nil {
                restoreActionButton.buttonStyle(.borderedProminent)
            } else {
                restoreActionButton.buttonStyle(.bordered)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.accentColor)
        .disabled(backup == nil || restoring)
        // Attach the confirmation to its source button so iPad popovers anchor correctly.
        .confirmationDialog("Restore Settings?", isPresented: $showingRestoreConfirmation, titleVisibility: .visible) {
            Button("Restore Settings", role: .destructive) {
                Task { await restore() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This restores settings in Open Loop. Disconnect and unpair your pump before restoring; review therapy settings before pairing again."
            )
        }
    }

    private var restoreActionButton: some View {
        Button {
            guard let backup else { return }
            if let onSelectForOnboarding {
                onSelectForOnboarding(backup)
                dismiss()
            } else {
                showingRestoreConfirmation = true
            }
        } label: {
            actionLabel(
                onSelectForOnboarding == nil ? "Restore Settings" : "Select Backup",
                systemImage: onSelectForOnboarding == nil ? "icloud.and.arrow.down" : nil,
                color: onSelectForOnboarding == nil ? (colorScheme == .dark ? .bgDarkBlue : .white) : .accentColor
            )
        }
    }

    private var exportButton: some View {
        Button {
            guard let backup, !restoring else { return }
            do {
                exported = TrioCloudBackupFile(url: try TrioCloudBackupCoordinator.exportBackupFile(backup))
            } catch { message = error.localizedDescription }
        } label: {
            actionLabel("Export Backup File", systemImage: "square.and.arrow.up", color: .accentColor)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.accentColor)
        .disabled(backup == nil || restoring)
    }

    private func actionLabel(_ title: LocalizedStringKey, systemImage: String?, color: Color) -> some View {
        HStack {
            if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
            Spacer(minLength: 0)
            Text(title).multilineTextAlignment(.center)
            Spacer(minLength: 0)
            // Match the leading icon's width to keep the title centered.
            if let systemImage { Image(systemName: systemImage).hidden().accessibilityHidden(true) }
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .bold()
    }

    @MainActor private func restore() async {
        guard let backup, !restoring else { return }
        restoring = true
        defer { restoring = false }
        do {
            try await TrioCloudBackupCoordinator.shared.restoreConfiguredApp(backup)
            restored = true
        } catch {
            message = "Restore stopped. No pump settings were sent.\n\n" + error.localizedDescription
        }
    }
}

