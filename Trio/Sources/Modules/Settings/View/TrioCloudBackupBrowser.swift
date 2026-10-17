import SwiftUI

struct TrioCloudBackupBrowser: View {
    var onSelectForOnboarding: ((TrioSettingsBackup) -> Void)? = nil
    var selectedBackupID: String? = nil
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @State private var backups: [TrioCloudBackupEntry] = []
    @State private var error: String?
    @State private var loading = false
    @State private var didRequestInitialLoad = false
    @State private var modifying = false
    @State private var selected: TrioCloudBackupEntry?
    @State private var deleting: TrioCloudBackupEntry?
    @State private var renaming: TrioCloudBackupEntry?
    @State private var renameName = ""
    private var busy: Bool { loading || modifying }
    private var canManage: Bool { onSelectForOnboarding == nil }
    private let sectionOrder: [TrioSettingsBackup.Origin] = [.manual, .automatic]

    var body: some View {
        Group {
            if !canManage {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("Choose a backup to restore.").font(.headline)
                        Spacer()
                        refreshButton
                    }
                    status
                    ForEach(sectionOrder, id: \.self) { origin in
                        let entries = backups.filter { $0.origin == origin }
                        if !entries.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(sectionTitle(origin))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)
                                VStack(spacing: 0) {
                                    ForEach(entries) { entry in
                                        backupRow(entry).padding()
                                        if entry.id != entries.last?.id { Divider().padding(.horizontal) }
                                    }
                                }
                                .background(Color.chart.opacity(0.65))
                                .cornerRadius(10)
                            }
                        }
                    }
                }
            } else {
                List {
                    status
                    ForEach(sectionOrder, id: \.self) { origin in
                        Section(sectionTitle(origin)) {
                            let entries = backups.filter { $0.origin == origin }
                            ForEach(entries) { entry in
                                backupRow(entry)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) { managementActions(entry) }
                                    .contextMenu { managementActions(entry, inContextMenu: true) }
                            }
                            if entries.isEmpty && !loading { Text("No backups found").foregroundStyle(.secondary) }
                        }.listRowBackground(Color.chart)
                    }
                }
                .listSectionSpacing(sectionSpacing)
                .scrollContentBackground(.hidden)
                .background(appState.trioBackgroundColor(for: colorScheme))
                .navigationTitle("View Backups")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { refreshButton } }
            }
        }
        .task {
            guard !didRequestInitialLoad else { return }
            didRequestInitialLoad = true
            await refresh()
        }
        .sheet(item: $selected) { entry in
            NavigationStack {
                TrioCloudBackupDetailView(
                    entry: entry, onSelectForOnboarding: onSelectForOnboarding
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .alert("Delete Backup?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                guard let entry = deleting else { return }
                deleting = nil
                Task { await delete(entry) }
            }
        } message: { Text("This removes the backup from iCloud.") }
        .alert("Rename Backup", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameName)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                guard let entry = renaming else { return }
                let requestedName = renameName
                renaming = nil
                Task { await rename(entry, name: requestedName) }
            }
            .disabled(TrioSettingsBackup.normalizedName(renameName) == nil)
        }
    }

    private func sectionTitle(_ origin: TrioSettingsBackup.Origin) -> String {
        origin == .manual ? String(localized: "Manual Backups") : String(localized: "Automatic Backups")
    }

    private func backupRow(_ entry: TrioCloudBackupEntry) -> some View {
        Button { selected = entry } label: {
            HStack {
                TrioCloudBackupRow(entry: entry)
                Spacer()
                if selectedBackupID == entry.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedBackupID == entry.id ? .isSelected : [])
        .disabled(busy)
    }

    @ViewBuilder private func managementActions(_ entry: TrioCloudBackupEntry, inContextMenu: Bool = false) -> some View {
        Button(role: .destructive) { deleting = entry } label: {
            Label {
                Text("Delete")
            } icon: {
                Image(systemName: "trash")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(inContextMenu ? Color.red : Color.white)
            }
        }
        .tint(.red)
        .disabled(busy)
        if entry.origin == .manual && entry.validationMessage == nil {
            Button { renameName = entry.name ?? ""
                renaming = entry } label: { Label("Rename", systemImage: "pencil") }
                .tint(.accentColor)
                .disabled(busy)
        }
    }

    private var refreshButton: some View {
        Button { Task { await refresh() } } label: {
            Group {
                if loading { ProgressView().tint(.primary) }
                else { Image(systemName: "arrow.clockwise").foregroundStyle(.primary) }
            }
            .frame(width: 24, height: 24)
        }
        .tint(.primary)
        .accessibilityLabel("Refresh backups")
        .disabled(busy)
    }

    @ViewBuilder private var status: some View {
        if let error { Text(error).foregroundStyle(.secondary).listRowBackground(Color.chart) }
        if !canManage && backups.isEmpty && !busy && error == nil {
            Text("No backups found").foregroundStyle(.secondary)
        }
    }

    @MainActor private func refresh() async {
        guard !busy else { return }
        loading = true
        defer { loading = false }
        do { backups = try await TrioCloudBackupCoordinator.shared.listBackups()
            error = nil } catch { self.error = error.localizedDescription }
    }

    @MainActor private func delete(_ entry: TrioCloudBackupEntry) async {
        guard !busy else { return }
        modifying = true
        defer { modifying = false }
        do {
            try await TrioCloudBackupCoordinator.shared.deleteBackup(id: entry.id)
            backups.removeAll { $0.id == entry.id }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    @MainActor private func rename(_ entry: TrioCloudBackupEntry, name: String) async {
        guard !busy else { return }
        modifying = true
        defer { modifying = false }
        do {
            let updated = try await TrioCloudBackupCoordinator.shared.renameBackup(id: entry.id, name: name)
            if let index = backups.firstIndex(where: { $0.id == entry.id }) { backups[index] = updated }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}


private struct TrioCloudBackupRow: View {
    let entry: TrioCloudBackupEntry
    private var title: String { entry.name ?? (entry.origin == .manual ? "Manual Backup" : "Automatic Backup") }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(.primary)
            if let warning = entry.validationMessage {
                Text(warning).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(entry.createdAt, format: .dateTime.month().day().year().hour().minute())
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
