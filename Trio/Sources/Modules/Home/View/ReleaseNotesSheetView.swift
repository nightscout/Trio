import SwiftUI

/// Body of a release's notes: its summary, any GitHub alert callouts, and the bullets from its
/// "What's Changed At A Glance" section. The full notes, including the pull request lists, stay on
/// GitHub behind the link at the bottom.
struct ReleaseNotesContentView: View {
    let notes: ReleaseNotes

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(notes.name)
                .font(.largeTitle)
                .bold()
                .frame(maxWidth: .infinity, alignment: .leading)

            if !notes.summary.isEmpty {
                Text(markdown(notes.summary))
                    .font(.body)
            }

            ForEach(notes.callouts) { callout in
                calloutView(callout)
            }

            if !notes.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What's Changed At A Glance", comment: "Heading above the release note highlights")
                        .font(.headline)

                    ForEach(notes.highlights) { highlight in
                        highlightRow(highlight)
                    }
                }
            }

            Button {
                if let url = notes.url {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Text("Read the full release notes", comment: "Link to the complete release notes on GitHub")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                }
            }
            .disabled(notes.url == nil)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    // MARK: - Subviews

    @ViewBuilder private func highlightRow(_ highlight: ReleaseNotes.Highlight) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: highlight.level > 0 ? "◦" : "•")
                .foregroundStyle(.secondary)

            Group {
                if highlight.subject.isEmpty {
                    Text(markdown(highlight.detail))
                } else if highlight.detail.isEmpty {
                    Text(highlight.subject).bold()
                } else {
                    Text(highlight.subject).bold() + Text(verbatim: " — ") + Text(markdown(highlight.detail))
                }
            }
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(highlight.level) * 16)
    }

    @ViewBuilder private func calloutView(_ callout: ReleaseNotes.Callout) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol(for: callout.kind))
                .foregroundStyle(tint(for: callout.kind))

            Text(markdown(callout.text))
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(tint(for: callout.kind).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    /// Renders inline Markdown, falling back to the raw text if it cannot be parsed.
    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private func symbol(for kind: ReleaseNotes.Callout.Kind) -> String {
        switch kind {
        case .note: return "info.circle.fill"
        case .tip: return "lightbulb.fill"
        case .important: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .caution: return "exclamationmark.octagon.fill"
        }
    }

    private func tint(for kind: ReleaseNotes.Callout.Kind) -> Color {
        switch kind {
        case .note: return .blue
        case .tip: return .green
        case .important: return .purple
        case .warning: return .orange
        case .caution: return .red
        }
    }
}

/// Full-height sheet raised from the Home panel, which the user acknowledges to dismiss the panel.
struct ReleaseNotesSheetView: View {
    let notes: ReleaseNotes

    /// Called when the user dismisses the sheet with the acknowledge button.
    ///
    /// Not called when the sheet is swiped away, so the Home panel survives an accidental
    /// dismissal and the notes can still be found.
    let onAcknowledge: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            ScrollView {
                ReleaseNotesContentView(notes: notes)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle(Text("What's New?", comment: "Navigation title of the release notes sheet"))
            .navigationBarTitleDisplayMode(.inline)

            Button {
                onAcknowledge()
                dismiss()
            } label: {
                Text("Got it!", comment: "Dismiss button for the release notes sheet")
                    .bold()
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
            }
            .buttonStyle(.bordered)
            .padding([.horizontal, .bottom])
            .padding(.top, 4)
            .background(appState.trioBackgroundColor(for: colorScheme))
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// Pushed from Settings, where the notes are browsed rather than acknowledged.
struct ReleaseNotesDetailView: View {
    let notes: ReleaseNotes

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            ReleaseNotesContentView(notes: notes)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle(notes.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
