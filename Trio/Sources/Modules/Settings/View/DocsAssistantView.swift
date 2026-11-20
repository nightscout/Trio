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
/// Presented as a sheet from the settings search. The questions and answers stay on screen for as long as the sheet is
/// open and are discarded when it closes. Every question is still answered on its own: earlier exchanges are not
/// passed to the model.
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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(model.exchanges) { exchange in
                            questionBubble(exchange.question)
                                .id(exchange.id)

                            if model.status == .available {
                                answerView(exchange)
                            }
                        }

                        if model.status != .available {
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
                .onChange(of: model.exchanges.last?.id) { _, newest in
                    guard let newest else { return }
                    // Bring the new question to the top so its answer has room to grow below it.
                    withAnimation(.smooth) {
                        proxy.scrollTo(newest, anchor: .top)
                    }
                }
            }
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

    /// One of the user's questions, trailing-aligned like an outgoing message.
    private func questionBubble(_ question: String) -> some View {
        HStack {
            Spacer(minLength: 48)
            Text(question)
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

    @ViewBuilder private func answerView(_ exchange: DocsAssistantViewModel.Exchange) -> some View {
        switch exchange.phase {
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

                Text(attributedAnswer(exchange.answer))
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if exchange.phase == .answering {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(Text("Writing the answer"))
                } else if !exchange.sources.isEmpty {
                    sourcesView(exchange.sources)
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
                        model.retry()
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

    private func sourcesView(_ sources: [DocsAssistantSource]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From the Trio documentation", comment: "Heading above the documentation sections an answer was based on")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
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

    private func attributedAnswer(_ answer: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: answer, options: options)) ?? AttributedString(answer)
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

/// Drives one question at a time through `DocsAssistant` and keeps the exchanges of the current sheet.
///
/// The conversation lives only in memory: it is gone as soon as the sheet, and with it this model, is released.
@MainActor @Observable final class DocsAssistantViewModel {
    enum Phase: Equatable {
        case idle
        case searching
        case answering
        case finished
        case failed(String)
    }

    /// One question together with the answer it got.
    struct Exchange: Identifiable {
        let id = UUID()
        let question: String
        var answer = ""
        var sources: [DocsAssistantSource] = []
        var phase: Phase = .idle
    }

    /// All questions asked since the sheet was opened, oldest first.
    private(set) var exchanges: [Exchange] = []
    private(set) var status = DocsAssistantSupport.status

    private var task: Task<Void, Never>?

    /// Progress of the newest exchange.
    var phase: Phase {
        exchanges.last?.phase ?? .idle
    }

    var isBusy: Bool {
        phase == .searching || phase == .answering
    }

    func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        stopCurrentAnswer()
        status = DocsAssistantSupport.status

        var exchange = Exchange(question: trimmed)
        guard status == .available else {
            exchanges.append(exchange)
            return
        }
        exchange.phase = .searching
        exchanges.append(exchange)
        let id = exchange.id

        task = Task { [weak self] in
            guard let self else { return }
            #if canImport(FoundationModels)
                if #available(iOS 26.0, *) {
                    do {
                        for try await event in DocsAssistant().ask(trimmed) {
                            if Task.isCancelled { return }
                            switch event {
                            case .searching:
                                update(id) { $0.phase = .searching }
                            case let .sources(sources):
                                update(id) { $0.sources = sources }
                            case let .answer(text):
                                update(id) {
                                    $0.answer = text
                                    $0.phase = .answering
                                }
                            case .finished:
                                update(id) { $0.phase = .finished }
                            }
                        }
                        update(id) {
                            if $0.phase == .answering || $0.phase == .searching {
                                $0.phase = .finished
                            }
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        if !Task.isCancelled {
                            update(id) { $0.phase = .failed(error.localizedDescription) }
                        }
                    }
                    return
                }
            #endif
            update(id) { $0.phase = .failed(DocsAssistantError.unavailable(.unsupportedOS).localizedDescription) }
        }
    }

    /// Asks the newest question again, replacing its failed attempt.
    func retry() {
        guard let last = exchanges.last, !isBusy else { return }
        exchanges.removeLast()
        ask(last.question)
    }

    private func update(_ id: Exchange.ID, _ change: (inout Exchange) -> Void) {
        guard let index = exchanges.lastIndex(where: { $0.id == id }) else { return }
        change(&exchanges[index])
    }

    /// Cancels a running answer and keeps what was written so far.
    private func stopCurrentAnswer() {
        task?.cancel()
        task = nil
        guard isBusy, let id = exchanges.last?.id else { return }
        update(id) { $0.phase = .finished }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
