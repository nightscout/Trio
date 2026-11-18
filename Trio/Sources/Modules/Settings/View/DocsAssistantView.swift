import SwiftUI

/// A free-text question typed into the settings search bar, to be answered by the on-device docs assistant.
struct DocsAssistantQuery: Identifiable, Hashable {
    let id = UUID()
    let question: String
}

/// "Trioneer", the little robot that fronts the docs assistant.
///
/// Drawn from plain shapes because SF Symbols has no robot glyph. The three lights in its mouth stand for Trio.
struct TrioneerMascot: View {
    var size: CGFloat = 40

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hue: 0.52, saturation: 0.75, brightness: 0.95),
                Color(hue: 0.62, saturation: 0.75, brightness: 0.95),
                Color(hue: 0.75, saturation: 0.65, brightness: 0.90)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            // Antenna
            Capsule()
                .fill(gradient)
                .frame(width: size * 0.06, height: size * 0.2)
                .offset(y: -size * 0.34)
            Circle()
                .fill(Color.orange)
                .frame(width: size * 0.16, height: size * 0.16)
                .offset(y: -size * 0.42)

            // Ears
            HStack(spacing: size * 0.8) {
                Capsule().fill(gradient).frame(width: size * 0.1, height: size * 0.26)
                Capsule().fill(gradient).frame(width: size * 0.1, height: size * 0.26)
            }
            .offset(y: size * 0.1)

            // Head
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(gradient)
                .frame(width: size * 0.8, height: size * 0.62)
                .offset(y: size * 0.1)

            // Eyes
            HStack(spacing: size * 0.16) {
                eye
                eye
            }
            .offset(y: size * 0.02)

            // Mouth: three lights, one per "Trio"
            HStack(spacing: size * 0.05) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: size * 0.07, height: size * 0.07)
                }
            }
            .offset(y: size * 0.26)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var eye: some View {
        Circle()
            .fill(Color.white)
            .frame(width: size * 0.2, height: size * 0.2)
            .overlay(
                Circle()
                    .fill(Color.black.opacity(0.75))
                    .frame(width: size * 0.09, height: size * 0.09)
            )
    }
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
                VStack(alignment: .leading, spacing: 24) {
                    questionBubble

                    if model.status == .available {
                        answerView
                    } else {
                        unavailableView
                    }

                    disclaimer
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .animation(.smooth, value: model.phase)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("Trioneer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if #available(iOS 26.0, *) {
                        Button(role: .close) {
                            dismiss()
                        }
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                        }
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
        .presentationDragIndicator(.visible)
        .task { model.ask(initialQuestion) }
        .onDisappear { model.cancel() }
    }

    // MARK: - Sections

    /// The user's question, trailing-aligned like an outgoing message.
    private var questionBubble: some View {
        HStack {
            Spacer(minLength: 48)
            Text(model.question)
                .font(.body)
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Color.accentColor,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
        }
    }

    /// Mascot and name above everything Trioneer says.
    private var answerHeader: some View {
        HStack(spacing: 8) {
            TrioneerMascot(size: 28)
            Text("Trioneer")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var answerView: some View {
        switch model.phase {
        case .idle:
            EmptyView()

        case .searching:
            VStack(alignment: .leading, spacing: 12) {
                answerHeader
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Searching the Trio documentation…")
                        .foregroundStyle(.secondary)
                }
            }

        case .answering,
             .finished:
            VStack(alignment: .leading, spacing: 12) {
                answerHeader

                Text(attributedAnswer)
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if model.phase == .answering {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(Text("Writing the answer"))
                } else if !model.sources.isEmpty {
                    sourcesView
                        .padding(.top, 12)
                }
            }

        case let .failed(message):
            VStack(alignment: .leading, spacing: 12) {
                answerHeader
                VStack(alignment: .leading, spacing: 12) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Button {
                        model.ask(model.question)
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.chart, in: Self.cardShape)
            }
        }
    }

    private static let cardShape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    private var sourcesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From the Trio documentation", comment: "Heading above the documentation sections an answer was based on")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(model.sources.enumerated()), id: \.element.id) { index, source in
                    if index > 0 {
                        Divider().padding(.leading, 52)
                    }
                    if let url = source.url {
                        SwiftUI.Link(destination: url) {
                            sourceRow(source, opensLink: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        sourceRow(source, opensLink: false)
                    }
                }
            }
            .background(Color.chart, in: Self.cardShape)
        }
    }

    private func sourceRow(_ source: DocsAssistantSource, opensLink: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.section)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(source.page)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            if opensLink {
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private var unavailableView: some View {
        ContentUnavailableView {
            Label(
                String(localized: "Apple Intelligence isn't available", comment: "Docs assistant unavailable heading"),
                systemImage: "sparkles"
            )
        } description: {
            Text(DocsAssistantError.unavailable(model.status).errorDescription ?? "")
        } actions: {
            SwiftUI.Link(destination: Self.docsURL) {
                Label(
                    String(
                        localized: "Open Trio Docs in the browser",
                        comment: "Link shown when the on-device assistant is unavailable"
                    ),
                    systemImage: "safari"
                )
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
        .frame(maxWidth: .infinity)
    }

    private var disclaimer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle")
                .accessibilityHidden(true)
            Text(
                "Answers are created on your iPhone from the Trio documentation and can be incomplete or wrong. They are not medical advice. Talk to your diabetes care team before you change your therapy settings.",
                comment: "Disclaimer below every answer of the on-device docs assistant"
            )
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    /// Floating input field: Liquid Glass on iOS 26 and later, material below.
    private var inputBar: some View {
        let canSend = !trimmedDraft.isEmpty && !model.isBusy
        return HStack(spacing: 8) {
            TextField(
                String(localized: "Ask another question", comment: "Placeholder of the docs assistant input field"),
                text: $draft
            )
            .submitLabel(.send)
            .focused($draftIsFocused)
            .onSubmit(submitDraft)
            .padding(.leading, 16)
            .frame(minHeight: 44)

            Button(action: submitDraft) {
                Image(systemName: "arrow.up")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(canSend ? Color.accentColor : Color.secondary.opacity(0.35), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(Text("Ask"))
        }
        .padding(.trailing, 2)
        .modifier(DocsInputBarBackground())
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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

/// Capsule behind the docs assistant input field.
///
/// Liquid Glass on iOS 26 and later, material below, and an opaque fill with a visible rim when
/// Reduce Transparency or Increase Contrast is on.
private struct DocsInputBarBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        if reduceTransparency || colorSchemeContrast == .increased {
            content.background(
                Capsule()
                    .fill(Color(.secondarySystemBackground))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.4), lineWidth: 1))
            )
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
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
