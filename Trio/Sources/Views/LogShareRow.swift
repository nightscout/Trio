import SwiftUI

struct LogShareRow: View {
    let title: LocalizedStringKey
    var footnote: LocalizedStringKey?
    let kinds: [LogExport.Kind]
    let logExport: LogExport?

    @State private var showKinds = false
    @State private var showDays = false
    @State private var pendingKind: LogExport.Kind?
    @State private var isPreparing = false
    @State private var file: URL?
    @State private var showShareSheet = false
    @State private var showError = false

    var body: some View {
        VStack(alignment: .leading) {
            Button(action: start) {
                HStack {
                    Text(title)
                        .foregroundColor(.primary)
                    Spacer()
                    if isPreparing {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(isPreparing || logExport == nil || kinds.isEmpty)

            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .combine)
        .glassActionSheet(
            "Share Logs",
            message: Text("Your Nightscout address, passwords and device serial numbers are removed."),
            isPresented: $showKinds,
            actions: kinds.map { kind in
                GlassSheetAction(kind.label) { pendingKind = kind }
            }
        )
        .onChange(of: showKinds) { _, shown in
            // The sheet runs the chosen action before it clears its binding
            if !shown, pendingKind != nil {
                showDays = true
            }
        }
        .glassActionSheet(
            "How far back?",
            isPresented: $showDays,
            actions: [
                GlassSheetAction("Last 24 Hours") { share(days: 1) },
                GlassSheetAction("Last 3 Days") { share(days: 3) },
                GlassSheetAction("Last 7 Days") { share(days: 7) }
            ],
            onCancel: { pendingKind = nil }
        )
        .sheet(isPresented: $showShareSheet, onDismiss: discardFile) {
            ShareSheet(activityItems: file.map { [$0] } ?? [])
        }
        .alert("Could not prepare logs", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        }
    }

    private func start() {
        guard !isPreparing else { return }
        if kinds.count == 1 {
            pendingKind = kinds.first
            showDays = true
        } else {
            pendingKind = nil
            showKinds = true
        }
    }

    private func share(days: Int) {
        guard let kind = pendingKind, let logExport else { return }
        pendingKind = nil
        isPreparing = true
        Task { @MainActor in
            do {
                file = try await logExport.makeFile(kind, days: days)
                isPreparing = false
                showShareSheet = true
            } catch {
                isPreparing = false
                warning(.ui, "Preparing logs for sharing failed", error: error)
                showError = true
            }
        }
    }

    private func discardFile() {
        guard let file else { return }
        self.file = nil
        Task.detached(priority: .utility) {
            LogExport.discard(file)
        }
    }
}

private extension LogExport.Kind {
    var label: LocalizedStringKey {
        switch self {
        case .all: return "All Logs"
        case .pump: return "Pump Logs"
        case .cgm: return "CGM Logs"
        }
    }
}
