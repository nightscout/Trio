import SwiftUI

/// A free-text question typed into the settings search bar, to be answered by the on-device docs assistant.
struct DocsAssistantQuery: Identifiable, Hashable {
    let id = UUID()
    let question: String
}

/// Answers free-text questions about Trio on this device, based on the bundled Trio documentation.
///
/// Presented as a sheet from the settings search. Every question is answered on its own; there is no chat history.
struct DocsAssistantView: View {
    let initialQuestion: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    @State private var model = DocsAssistantViewModel()
    @State private var draft = ""
    @FocusState private var draftIsFocused: Bool

    private static let docsURL = URL(string: "https://triodocs.org/")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    questionView

                    if model.status == .available {
                        answerView
                    } else {
                        unavailableView
                    }

                    disclaimer
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(appState.trioBackgroundColor(for: colorScheme))
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("Ask Trio Docs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SwiftUI.Link(destination: Self.docsURL) {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel(Text("Open Trio Docs in the browser"))
                }
            }
        }
        .task { model.ask(initialQuestion) }
        .onDisappear { model.cancel() }
    }

    // MARK: - Sections

    private var questionView: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "questionmark.bubble")
                .foregroundColor(.accentColor)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(model.question)
                .font(.headline)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder private var answerView: some View {
        switch model.phase {
        case .idle:
            EmptyView()

        case .searching:
            HStack(spacing: 10) {
                ProgressView()
                Text("Searching the Trio documentation…")
                    .foregroundColor(.secondary)
            }

        case .answering,
             .finished:
            VStack(alignment: .leading, spacing: 16) {
                Text(attributedAnswer)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if model.phase == .answering {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(Text("Writing the answer"))
                } else if !model.sources.isEmpty {
                    sourcesView
                }
            }

        case let .failed(message):
            VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.secondary)
                Button {
                    model.ask(model.question)
                } label: {
                    Text("Try Again")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var sourcesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From the Trio documentation", comment: "Heading above the documentation sections an answer was based on")
                .font(.subheadline)
                .bold()

            ForEach(model.sources) { source in
                if let url = source.url {
                    SwiftUI.Link(destination: url) {
                        sourceRow(source)
                    }
                } else {
                    sourceRow(source)
                }
            }
        }
    }

    private func sourceRow(_ source: DocsAssistantSource) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.section)
                    .font(.subheadline)
                Text(source.page)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.up.right.square")
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
        }
        .padding(10)
        .background(Color.chart, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var unavailableView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                String(localized: "Apple Intelligence isn't available", comment: "Docs assistant unavailable heading"),
                systemImage: "sparkles"
            )
            .font(.headline)

            Text(DocsAssistantError.unavailable(model.status).errorDescription ?? "")
                .foregroundColor(.secondary)

            SwiftUI.Link(destination: Self.docsURL) {
                Label(
                    String(
                        localized: "Open Trio Docs in the browser",
                        comment: "Link shown when the on-device assistant is unavailable"
                    ),
                    systemImage: "safari"
                )
            }
        }
    }

    private var disclaimer: some View {
        Text(
            "Answers are created on your iPhone from the Trio documentation and can be incomplete or wrong. They are not medical advice. Talk to your diabetes care team before you change your therapy settings.",
            comment: "Disclaimer below every answer of the on-device docs assistant"
        )
        .font(.footnote)
        .foregroundColor(.secondary)
        .padding(.top, 8)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(
                String(localized: "Ask another question", comment: "Placeholder of the docs assistant input field"),
                text: $draft
            )
            .textFieldStyle(.roundedBorder)
            .submitLabel(.send)
            .focused($draftIsFocused)
            .onSubmit(submitDraft)

            Button(action: submitDraft) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(trimmedDraft.isEmpty || model.isBusy)
            .accessibilityLabel(Text("Ask"))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .disabled(model.status != .available)
    }

    // MARK: - Helpers

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var attributedAnswer: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: model.answer, options: options)) ?? AttributedString(model.answer)
    }

    private func submitDraft() {
        let question = trimmedDraft
        guard !question.isEmpty, !model.isBusy else { return }
        draft = ""
        draftIsFocused = false
        model.ask(question)
    }
}

/// Drives one question at a time through `DocsAssistant` and exposes its progress to the view.
@MainActor @Observable final class DocsAssistantViewModel {
    enum Phase: Equatable {
        case idle
        case searching
        case answering
        case finished
        case failed(String)
    }

    private(set) var question = ""
    private(set) var answer = ""
    private(set) var sources: [DocsAssistantSource] = []
    private(set) var phase: Phase = .idle
    private(set) var status = DocsAssistantSupport.status

    private var task: Task<Void, Never>?

    var isBusy: Bool {
        phase == .searching || phase == .answering
    }

    func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        task?.cancel()
        question = trimmed
        answer = ""
        sources = []
        status = DocsAssistantSupport.status

        guard status == .available else {
            phase = .idle
            return
        }
        phase = .searching

        task = Task { [weak self] in
            guard let self else { return }
            #if canImport(FoundationModels)
                if #available(iOS 26.0, *) {
                    do {
                        for try await event in DocsAssistant().ask(trimmed) {
                            if Task.isCancelled { return }
                            switch event {
                            case .searching:
                                phase = .searching
                            case let .sources(sources):
                                self.sources = sources
                            case let .answer(text):
                                answer = text
                                phase = .answering
                            case .finished:
                                phase = .finished
                            }
                        }
                        if phase == .answering || phase == .searching {
                            phase = .finished
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        if !Task.isCancelled {
                            phase = .failed(error.localizedDescription)
                        }
                    }
                    return
                }
            #endif
            phase = .failed(DocsAssistantError.unavailable(.unsupportedOS).localizedDescription)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
