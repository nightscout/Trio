import SwiftUI
import UIKit

struct DiagnosticReportView: View {
    let generator: DiagnosticReportGenerator?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    @State private var days = 3
    @State private var includeDebug = true
    @State private var isGenerating = false
    @State private var archive: URL?
    @State private var showShareSheet = false
    @State private var showCopied = false
    @State private var showError = false

    private static let dayOptions = [1, 3, 7]

    var body: some View {
        NavigationStack {
            List {
                Section(
                    content: {
                        Picker("Time window", selection: $days) {
                            ForEach(Self.dayOptions, id: \.self) { day in
                                day == 1 ? Text("1 day") : Text("\(day) days")
                            }
                        }
                        Toggle("Include debug lines", isOn: $includeDebug)
                    },
                    footer: {
                        Text("Identifiers such as URLs, secrets, and device serials are replaced before sharing.")
                    }
                )
                .listRowBackground(Color.chart)

                Section(
                    content: {
                        Button(action: share) {
                            HStack {
                                Text("Share Report")
                                Spacer()
                                if isGenerating {
                                    ProgressView()
                                }
                            }
                        }
                        Button(action: copyMarkdown) {
                            HStack {
                                Text("Copy Markdown")
                                Spacer()
                                if showCopied {
                                    Label("Copied", systemImage: "checkmark.circle.fill")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    },
                    footer: {
                        if showError {
                            Text("Could not prepare logs").foregroundColor(.red)
                        }
                    }
                )
                .disabled(isGenerating || generator == nil)
                .listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Diagnostic Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet, onDismiss: discardArchive) {
                ShareSheet(activityItems: archive.map { [$0] } ?? [])
            }
            .onDisappear(perform: discardArchive)
        }
    }

    private var window: DateInterval {
        let now = Date()
        return DateInterval(start: now.addingTimeInterval(-Double(days) * 24 * 60 * 60), end: now)
    }

    private func share() {
        run { generator in
            archive = try await generator.archive(window: window, includeDebug: includeDebug)
            showShareSheet = true
        }
    }

    private func copyMarkdown() {
        run { generator in
            UIPasteboard.general.string = try await generator.markdown(window: window, includeDebug: includeDebug)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { showCopied = true }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { showCopied = false }
        }
    }

    private func run(_ action: @escaping @MainActor(DiagnosticReportGenerator) async throws -> Void) {
        guard let generator else { return }
        isGenerating = true
        showError = false
        Task { @MainActor in
            do {
                try await action(generator)
            } catch {
                warning(.service, "Could not prepare diagnostic report: \(error)")
                showError = true
            }
            isGenerating = false
        }
    }

    private func discardArchive() {
        if let archive {
            LogShareAction.discard(archive)
        }
        archive = nil
    }
}
