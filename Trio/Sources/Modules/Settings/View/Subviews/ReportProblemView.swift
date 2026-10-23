import SwiftUI

struct ReportProblemView: View {
    @ObservedObject var state: Settings.StateModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

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
