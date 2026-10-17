import SwiftUI
import UniformTypeIdentifiers

struct TrioCloudBackupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @State private var operation: Operation?
    @State private var naming = false
    @State private var name = ""
    @State private var message: String?
    @State private var createdName: String?
    @State private var importing = false
    @State private var presentation: BackupPresentation?
    @State private var lastBackup: Date?

    private enum Operation: Equatable { case backup, export }

    private enum BackupPresentation: Identifiable {
        case exported(TrioCloudBackupFile)
        case imported(TrioSettingsBackup)

        var id: String {
            switch self {
            case let .exported(file): return file.id.uuidString
            case let .imported(backup): return backup.id.uuidString
            }
        }
    }

    var body: some View {
        ZStack {
            backupList
        }
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { lastBackup = TrioCloudBackupCoordinator.shared.lastSuccessfulBackupDate }
        .onReceive(Foundation.NotificationCenter.default.publisher(for: TrioCloudBackupCoordinator.uploadNotification)) { _ in
            lastBackup = TrioCloudBackupCoordinator.shared.lastSuccessfulBackupDate
        }
        .alert("Name Your Backup", isPresented: $naming) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Create Backup") {
                let requestedName = name
                Task { await perform(.backup) {
                    let entry = try await TrioCloudBackupCoordinator.shared.createManualBackup(name: requestedName)
                    createdName = entry.name ?? TrioSettingsBackup.normalizedName(requestedName)
                    name = ""
                } }
            }
            .disabled(TrioSettingsBackup.normalizedName(name) == nil)
        }
        .alert("Success!", isPresented: Binding(get: { createdName != nil }, set: { if !$0 { createdName = nil } })) {
            Button("Done", role: .cancel) {}
        } message: {
            Text("Your \"\(createdName ?? "")\" backup has been saved to iCloud.")
        }
        .alert("Backup & Restore", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
        .sheet(item: $presentation) { destination in
            switch destination {
            case let .exported(file):
                ShareSheet(activityItems: [file.url])
            case let .imported(backup):
                NavigationStack {
                    TrioCloudBackupDetailView(
                        entry: backup.entry, snapshot: backup, allowsExport: false, onSelectForOnboarding: nil
                    )
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let backup = try TrioSettingsBackup.decode(TrioSettingsBackup.readBackupData(from: url))
                // Let the importer close before presenting backup details.
                DispatchQueue.main.async { presentation = .imported(backup) }
            } catch {
                if (error as? CocoaError)?.code != .userCancelled { message = error.localizedDescription }
            }
        }
    }

    private var backupList: some View {
        List {
            Section {
                Button {
                    guard operation == nil, presentation == nil, !importing else { return }
                    name = ""
                    naming = true
                } label: {
                    HStack {
                        Text("Back Up Now")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(operation == .backup)
            } header: { Text("iCloud Backup") } footer: {
                Text(
                    lastBackup
                        .map { "Last successful backup: \($0.formatted(date: .abbreviated, time: .shortened))" } ??
                        "No recent backups."
                )
            }.listRowBackground(Color.chart)
            Section {
                NavigationLink("View Backups") { TrioCloudBackupBrowser() }
            }.listRowBackground(Color.chart)
            Section {
                NavigationLink("Configuration") { TrioCloudBackupConfigurationView() }
            }.listRowBackground(Color.chart)
            Section("Local Backup") {
                Button("Export Backup File") {
                    Task { await perform(.export) {
                        presentation = .exported(TrioCloudBackupFile(
                            url: try await TrioCloudBackupCoordinator.shared.exportBackupFile()
                        ))
                    } }
                }
                .buttonStyle(.borderless)
                .disabled(operation == .export)
                Button("Import Backup File") {
                    guard operation == nil, presentation == nil, !importing else { return }
                    importing = true
                }
                .buttonStyle(.borderless)
            }.listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .listSectionSpacing(sectionSpacing)
        .allowsHitTesting(operation == nil && !importing)
    }

    @MainActor private func perform(_ requestedOperation: Operation, action: () async throws -> Void) async {
        guard operation == nil, presentation == nil, !importing else { return }
        operation = requestedOperation
        defer { operation = nil
            lastBackup = TrioCloudBackupCoordinator.shared.lastSuccessfulBackupDate }
        do { try await action() } catch { message = error.localizedDescription }
    }
}

struct TrioCloudBackupFile: Identifiable {
    let id = UUID()
    let url: URL
}

private extension TrioSettingsBackup {
    var entry: TrioCloudBackupEntry {
        .init(id: id.uuidString, createdAt: createdAt, origin: origin, name: name, fingerprint: fingerprint)
    }
}

