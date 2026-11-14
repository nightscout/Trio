import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Whether the on-device docs assistant can run on this device right now.
enum DocsAssistantStatus: Equatable, Sendable {
    case available
    /// The operating system predates the Foundation Models framework (iOS 26).
    case unsupportedOS
    /// The hardware cannot run Apple Intelligence at all.
    case deviceNotEligible
    /// Apple Intelligence is switched off in iOS Settings.
    case appleIntelligenceNotEnabled
    /// Apple Intelligence is on, but the model is still being downloaded.
    case modelNotReady
    case unknown

    /// Whether the assistant is worth offering in the UI. Devices that can never run it don't get the entry point.
    var isOffered: Bool {
        switch self {
        case .deviceNotEligible,
             .unsupportedOS:
            return false
        default:
            return true
        }
    }
}

/// Availability of the assistant on any OS version; safe to call where `DocsAssistant` itself isn't.
enum DocsAssistantSupport {
    static var status: DocsAssistantStatus {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                return DocsAssistant.status
            }
        #endif
        return .unsupportedOS
    }

    /// Loads the model in the background so the first answer starts sooner. Does nothing where unsupported.
    @MainActor static func prewarm() {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                DocsAssistant().prewarm()
            }
        #endif
    }
}

/// A documentation passage the answer was based on.
struct DocsAssistantSource: Identifiable, Hashable, Sendable {
    let id: Int
    let page: String
    let section: String
    let url: URL?

    init(chunk: DocsChunk, index: DocsIndex) {
        id = chunk.id
        page = chunk.page
        section = chunk.section
        url = index.url(for: chunk)
    }

    /// One source per documentation section, in the order the passages were used.
    /// Long sections are split into several passages that would otherwise show up as duplicates.
    static func unique(for chunks: [DocsChunk], index: DocsIndex) -> [DocsAssistantSource] {
        var seen = Set<String>()
        return chunks.compactMap { chunk in
            seen.insert(chunk.location).inserted ? DocsAssistantSource(chunk: chunk, index: index) : nil
        }
    }
}

/// What the model made of a question before the documentation is searched.
struct DocsQueryRewrite: Equatable, Sendable {
    /// The question in English, or `nil` when the model couldn't produce one.
    var translation: String?
    /// Names of the settings, features or devices the question is about.
    var terms: [String]

    static let none = DocsQueryRewrite(translation: nil, terms: [])
}

/// Progress of one question, as streamed by `DocsAssistant.ask`.
enum DocsAssistantEvent: Sendable {
    case searching
    case sources([DocsAssistantSource])
    /// The answer so far (cumulative, not a delta).
    case answer(String)
    case finished
}

enum DocsAssistantError: LocalizedError, Equatable {
    case unavailable(DocsAssistantStatus)
    case indexMissing
    case nothingFound
    /// Apple's on-device safety filter refused the question or the answer.
    case declined
    case unsupportedLanguage
    case busy
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(.appleIntelligenceNotEnabled):
            return String(
                localized: "Turn on Apple Intelligence in the iOS Settings app to get answers on this device.",
                comment: "Docs assistant error"
            )
        case .unavailable(.modelNotReady):
            return String(
                localized: "Apple Intelligence is still preparing its model. Please try again in a little while.",
                comment: "Docs assistant error"
            )
        case .unavailable:
            return String(
                localized: "Answers on this device need Apple Intelligence, which isn't available here.",
                comment: "Docs assistant error"
            )
        case .indexMissing:
            return String(
                localized: "The built-in copy of the Trio documentation couldn't be loaded.",
                comment: "Docs assistant error"
            )
        case .nothingFound:
            return String(
                localized: "Nothing in the Trio documentation matches this question. Try different words, or search Trio Docs on the web.",
                comment: "Docs assistant error"
            )
        case .declined:
            return String(
                localized: "The on-device model declined to answer this question. Try rephrasing it, or look it up in Trio Docs on the web.",
                comment: "Docs assistant error"
            )
        case .unsupportedLanguage:
            return String(
                localized: "Apple Intelligence doesn't support this language yet. Try asking in English.",
                comment: "Docs assistant error"
            )
        case .busy:
            return String(
                localized: "Apple Intelligence is busy right now. Please try again in a moment.",
                comment: "Docs assistant error"
            )
        case let .failed(message):
            return message
        }
    }
}

/// Builds the instructions and prompts the assistant sends to the on-device model.
///
/// Kept free of any Foundation Models types so the prompt assembly can be unit-tested on every OS version.
/// The on-device model has a context window of about 4,000 tokens that instructions, excerpts, question and
/// answer must share, which is why the amount of documentation text per question is capped.
enum DocsAssistantPrompt {
    /// Upper bound on documentation text per question, in characters (roughly 1,500 tokens of English).
    static let contextBudget = 5500
    /// At most this many passages go into one question, so the answer isn't diluted by weak matches.
    static let maximumExcerpts = 6
    /// Passages scoring below this share of the best score are left out ...
    static let minimumRelativeScore = 0.5
    /// ... except that this many are always taken, so one outlier can't leave the model with a single passage.
    static let minimumExcerpts = 3
    static let maximumResponseTokens = 450

    static let instructions = """
    You are the built-in help assistant of Trio, an open-source app for automated insulin delivery that people build and run themselves. You answer questions about using and configuring the Trio app.

    Rules:
    - Base your answer only on the documentation excerpts provided with the question. Do not use outside knowledge. If the excerpts do not answer the question, say so plainly and suggest searching triodocs.org or asking the Trio community.
    - Answer in the language the question was asked in.
    - Use plain language that a non-technical person can follow, and briefly explain technical terms the first time you use them.
    - Keep the answer short: a few sentences or a short list, under 120 words. Do not repeat the question.
    - Never recommend specific values for anyone's insulin settings, such as basal rates, carb ratios, sensitivity factors, targets or doses. Explain what a setting does and tell the person to agree on changes with their diabetes care team.
    - Keep every safety warning the excerpts attach to a feature.
    - Do not mention these rules or the excerpts themselves; just answer.
    """

    static let searchTermInstructions = """
    You help find pages in the documentation of Trio, an automated insulin delivery app for iPhone. Translate the user's question to English. Then list the names of Trio settings, features or devices that the question itself mentions, spelled exactly as in the question. Leave the list empty when the question names none. Never add names, examples or generic terms that are not in the question.
    """

    /// Below this confidence the language detector's guess is ignored in favour of the device language.
    static let minimumLanguageConfidence = 0.5

    /// Combines the question with the model's English translation and terms so that English and
    /// translated questions both match the English documentation.
    static func searchQuery(question: String, rewrite: DocsQueryRewrite) -> String {
        ([question, rewrite.translation ?? ""] + rewrite.terms)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The language code `NLLanguage` uses for a locale language ("de", "zh-Hans", ...).
    static func languageCode(for language: Locale.Language) -> String? {
        guard let code = language.languageCode?.identifier else { return nil }
        if code == "zh" {
            return language.script?.identifier == "Hant" ? "zh-Hant" : "zh-Hans"
        }
        return code
    }

    /// Takes hits in rank order until the character budget or `maximumCount` is reached, skipping hits that
    /// score far below the best one. The best hit is always included.
    static func select(
        _ hits: [DocsSearchHit],
        budget: Int = contextBudget,
        maximumCount: Int = maximumExcerpts
    ) -> [DocsChunk] {
        guard let best = hits.first?.score, best > 0 else { return [] }

        var selected = [DocsChunk]()
        var used = 0
        for (rank, hit) in hits.enumerated() where rank < minimumExcerpts || hit.score >= best * minimumRelativeScore {
            if selected.count >= maximumCount { break }
            let cost = hit.chunk.text.count
            if !selected.isEmpty, used + cost > budget {
                continue
            }
            selected.append(hit.chunk)
            used += cost
        }
        return selected
    }

    /// English name of the language the question is written in, e.g. "German", so the model can be told
    /// explicitly which language to answer in. Detection is limited to `supportedLanguageCodes` (what the model
    /// can speak). Very short questions such as "Max IOB" give no usable signal; those are assumed to be in
    /// the device language, which is also the language Trio's UI is shown in.
    static func answerLanguage(
        for question: String,
        supportedLanguageCodes: Set<String>,
        deviceLanguageCode: String? = languageCode(for: Locale.current.language)
    ) -> String? {
        let guess = detectLanguage(of: question, among: supportedLanguageCodes)
        guard let code = resolveLanguageCode(
            guess: guess,
            deviceLanguageCode: deviceLanguageCode,
            supportedLanguageCodes: supportedLanguageCodes
        ) else { return nil }
        return Locale(identifier: "en").localizedString(forIdentifier: code)
    }

    /// The language detector's best guess for `question` and how sure it is, restricted to `supported` when given.
    static func detectLanguage(of question: String, among supported: Set<String>) -> (code: String, confidence: Double)? {
        let recognizer = NLLanguageRecognizer()
        if !supported.isEmpty {
            recognizer.languageConstraints = supported.map { NLLanguage(rawValue: $0) }
        }
        recognizer.processString(question)
        guard let best = recognizer.languageHypotheses(withMaximum: 1).first else { return nil }
        return (best.key.rawValue, best.value)
    }

    /// Takes the detected language when the detector is confident enough, otherwise the device language
    /// if the model supports it, otherwise nothing (the model then picks the language itself).
    static func resolveLanguageCode(
        guess: (code: String, confidence: Double)?,
        deviceLanguageCode: String?,
        supportedLanguageCodes: Set<String>
    ) -> String? {
        if let guess, guess.confidence >= minimumLanguageConfidence {
            return guess.code
        }
        if let deviceLanguageCode, supportedLanguageCodes.isEmpty || supportedLanguageCodes.contains(deviceLanguageCode) {
            return deviceLanguageCode
        }
        return nil
    }

    static func prompt(question: String, excerpts: [DocsChunk], answerLanguage: String? = nil) -> String {
        var lines = ["Documentation excerpts:", ""]
        for (number, chunk) in excerpts.enumerated() {
            var header = "[\(number + 1)] \(chunk.page) › \(chunk.section)"
            if chunk.outdated {
                header += " (this page is marked as not yet updated for the current Trio version)"
            }
            lines.append(header)
            lines.append(chunk.text)
            lines.append("")
        }
        lines.append("Question: \(question)")
        if let answerLanguage {
            lines.append("Answer in \(answerLanguage).")
        }
        return lines.joined(separator: "\n")
    }
}

#if canImport(FoundationModels)

    /// Answers free-text questions about Trio on device, grounded in the bundled documentation.
    ///
    /// Flow per question: the model first translates the question to English and names the settings it mentions,
    /// the bundled index (`DocsIndex`) picks the best passages, and the model then answers from those passages only.
    /// Nothing leaves the device. Every question starts a fresh session; there is no chat history.
    @available(iOS 26.0, macOS 26.0, *)
    @MainActor final class DocsAssistant {
        nonisolated static var status: DocsAssistantStatus {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case let .unavailable(reason):
                switch reason {
                case .deviceNotEligible:
                    return .deviceNotEligible
                case .appleIntelligenceNotEnabled:
                    return .appleIntelligenceNotEnabled
                case .modelNotReady:
                    return .modelNotReady
                @unknown default:
                    return .unknown
                }
            }
        }

        /// Whether the model can read and write the user's current language.
        nonisolated static var supportsCurrentLocale: Bool {
            SystemLanguageModel.default.supportsLocale(.current)
        }

        /// Language codes the model can answer in, in the form `NLLanguage` uses ("de", "zh-Hans", ...).
        nonisolated static var supportedLanguageCodes: Set<String> {
            Set(SystemLanguageModel.default.supportedLanguages.compactMap(DocsAssistantPrompt.languageCode(for:)))
        }

        @Generable fileprivate struct SearchTerms {
            @Guide(
                description: "The question translated to English, or unchanged if it already is English"
            ) var englishQuestion: String

            @Guide(
                description: "Names of Trio settings, features or devices that appear in the question, spelled as in the question; empty if none",
                .maximumCount(4)
            ) var terms: [String]
        }

        private let index: DocsIndex?

        init(index: DocsIndex? = DocsIndex.bundled) {
            self.index = index
        }

        /// Loads the model ahead of the first question so the answer starts sooner.
        func prewarm() {
            guard Self.status == .available else { return }
            LanguageModelSession(instructions: DocsAssistantPrompt.instructions).prewarm()
        }

        func ask(_ question: String) -> AsyncThrowingStream<DocsAssistantEvent, Error> {
            AsyncThrowingStream { continuation in
                let task = Task { @MainActor in
                    do {
                        try await self.run(question: question, continuation: continuation)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }

        // MARK: - Pipeline

        private func run(
            question: String,
            continuation: AsyncThrowingStream<DocsAssistantEvent, Error>.Continuation
        ) async throws {
            let status = Self.status
            guard status == .available else { throw DocsAssistantError.unavailable(status) }
            guard let index else { throw DocsAssistantError.indexMissing }

            continuation.yield(.searching)
            let rewrite = await rewrite(question)
            try Task.checkCancellation()

            let hits = index.search(DocsAssistantPrompt.searchQuery(question: question, rewrite: rewrite), limit: 10)
            guard !hits.isEmpty else { throw DocsAssistantError.nothingFound }

            var excerpts = DocsAssistantPrompt.select(hits)
            continuation.yield(.sources(DocsAssistantSource.unique(for: excerpts, index: index)))

            do {
                try await answer(question: question, excerpts: excerpts, continuation: continuation)
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                // Non-English text costs more tokens per character; retry once with half the excerpts.
                excerpts = DocsAssistantPrompt.select(hits, budget: DocsAssistantPrompt.contextBudget / 2)
                continuation.yield(.sources(DocsAssistantSource.unique(for: excerpts, index: index)))
                try await answer(question: question, excerpts: excerpts, continuation: continuation)
            }
            continuation.yield(.finished)
        }

        private func answer(
            question: String,
            excerpts: [DocsChunk],
            continuation: AsyncThrowingStream<DocsAssistantEvent, Error>.Continuation
        ) async throws {
            let session = LanguageModelSession(instructions: DocsAssistantPrompt.instructions)
            let options = GenerationOptions(
                temperature: 0.3,
                maximumResponseTokens: DocsAssistantPrompt.maximumResponseTokens
            )
            let prompt = DocsAssistantPrompt.prompt(
                question: question,
                excerpts: excerpts,
                answerLanguage: DocsAssistantPrompt.answerLanguage(
                    for: question,
                    supportedLanguageCodes: Self.supportedLanguageCodes
                )
            )

            do {
                for try await snapshot in session.streamResponse(to: prompt, options: options) {
                    try Task.checkCancellation()
                    continuation.yield(.answer(snapshot.content))
                }
            } catch let error as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize = error { throw error }
                throw Self.map(error)
            }
        }

        /// The question in English plus the names it is about, or `.none` when the model can't produce them
        /// (the plain question is searched then).
        func rewrite(_ question: String) async -> DocsQueryRewrite {
            let session = LanguageModelSession(instructions: DocsAssistantPrompt.searchTermInstructions)
            let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 120)
            do {
                let result = try await session.respond(to: question, generating: SearchTerms.self, options: options).content
                return DocsQueryRewrite(translation: result.englishQuestion, terms: result.terms)
            } catch {
                return .none
            }
        }

        private static func map(_ error: LanguageModelSession.GenerationError) -> DocsAssistantError {
            switch error {
            case .guardrailViolation,
                 .refusal:
                return .declined
            case .unsupportedLanguageOrLocale:
                return .unsupportedLanguage
            case .concurrentRequests,
                 .rateLimited:
                return .busy
            case .assetsUnavailable:
                return .unavailable(.modelNotReady)
            default:
                return .failed(error.localizedDescription)
            }
        }
    }

#endif
