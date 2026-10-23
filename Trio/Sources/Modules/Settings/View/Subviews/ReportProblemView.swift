import SwiftUI

struct ReportProblemView: View {
    @ObservedObject var state: Settings.StateModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    @State private var sentReports: [SentReport] = []
    @State private var reportToDelete: SentReport?
    @State private var deletingID: String?
    @State private var deleteError: ReportSubmitError?

    var body: some View {
        List {
            Section {
                if let submitter = state.reportSubmitter {
                    NavigationLink(destination: SendReportView(
                        submitter: submitter,
                        logExport: state.logExport,
                        context: state.reportContext()
                    )) {
                        ReportOptionLabel(
                            title: "Send to the Trio Team",
                            footnote: "Private. Describe the problem, add screenshots and your logs. Only the Trio team can see it."
                        )
                    }
                }

                LogShareRow(
                    title: "Share Trio Logs",
                    footnote: "Save the file or send it to someone helping you on Discord or Facebook. Contains glucose, insulin and carbs; passwords and serial numbers are removed.",
                    kinds: state.logKinds,
                    logExport: state.logExport
                )
            }
            .listRowBackground(Color.chart)

            if let submitter = state.reportSubmitter, !sentReports.isEmpty {
                Section(
                    content: {
                        ForEach(sentReports) { report in
                            SentReportRow(
                                report: report,
                                isDeleting: deletingID == report.id,
                                onDelete: { reportToDelete = report }
                            )
                        }
                    },
                    header: { Text("Sent Reports") },
                    footer: { Text("Deleting a report removes it and its files from the Trio team's server.") }
                )
                .listRowBackground(Color.chart)
                .confirmationDialog(
                    "Delete Report?",
                    isPresented: Binding(get: { reportToDelete != nil }, set: { if !$0 { reportToDelete = nil } }),
                    titleVisibility: .visible,
                    presenting: reportToDelete
                ) { report in
                    Button("Delete Report", role: .destructive) { delete(report, with: submitter) }
                } message: { report in
                    Text("Report \(report.id) and its files will be deleted from the Trio team's server.")
                }
            }

            Section {
                ReportLinkRow(
                    title: "Open a GitHub Issue",
                    footnote: "Public. Only for bugs you can describe without personal or health data.",
                    url: "https://github.com/nightscout/Trio/issues/new/choose"
                )
            }
            .listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Report a Problem")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { sentReports = SentReports.load() }
        .alert(
            "Couldn't Delete Report",
            isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } }),
            presenting: deleteError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }

    private func delete(_ report: SentReport, with submitter: ReportSubmitting) {
        deletingID = report.id
        Task { @MainActor in
            do {
                try await submitter.withdraw(id: report.id)
            } catch {
                warning(.ui, "Deleting a problem report failed", error: error)
                deleteError = ReportSubmitError.from(error)
            }
            sentReports = SentReports.load()
            deletingID = nil
        }
    }
}

private struct SentReportRow: View {
    let report: SentReport
    let isDeleting: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: report.id)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                Text(report.date, format: .dateTime.day().month().year().hour().minute())
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isDeleting {
                ProgressView()
                    .accessibilityLabel(Text("Deleting"))
            } else {
                Menu {
                    Button {
                        UIPasteboard.general.string = report.id
                    } label: {
                        Label("Copy ID", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete Report", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel(Text("Report Actions"))
                }
            }
        }
    }
}

private struct ReportOptionLabel: View {
    let title: LocalizedStringKey
    var footnote: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundColor(.primary)
            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ReportLinkRow: View {
    let title: LocalizedStringKey
    var footnote: LocalizedStringKey?
    let url: String
    var hint: LocalizedStringKey?

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = URL(string: url) {
                openURL(url)
            }
        } label: {
            HStack {
                ReportOptionLabel(title: title, footnote: footnote)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .foregroundColor(.secondary)
                    .font(.footnote)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isLink)
        .accessibilityHint(hint.map { Text($0) } ?? Text(verbatim: ""))
    }
}
