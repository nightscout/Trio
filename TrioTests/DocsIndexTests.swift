import Foundation
import Testing

@testable import Trio

@Suite("Docs Index") struct DocsIndexTests {
    private let baseURL = URL(string: "https://triodocs.org/")!

    private func sampleIndex() -> DocsIndex {
        DocsIndex(
            chunks: [
                DocsChunk(
                    id: 0,
                    location: "configuration/settings/algorithm/autosens/#sensitivity-ratio",
                    page: "Autosens",
                    section: "Sensitivity Ratio",
                    text: "The Sensitivity Ratio is used to calculate the amount of adjustment Autosens applies to ISF, CR and basal."
                ),
                DocsChunk(
                    id: 1,
                    location: "configuration/settings/algorithm/smb-settings/#enable-smb-always",
                    page: "SMB Settings",
                    section: "Enable SMB Always",
                    text: "Allows super micro boluses at any time, regardless of carbs or temp targets."
                ),
                DocsChunk(
                    id: 2,
                    location: "configuration/services/nightscout/#upload",
                    page: "Nightscout",
                    section: "Upload",
                    text: "Trio can upload glucose, treatments and device status to your Nightscout site."
                )
            ],
            baseURL: baseURL,
            generated: "2026-01-01"
        )
    }

    // MARK: - Tokenizer

    @Test("Tokenizer lowercases, drops stop words and stems common suffixes") func tokenizer() {
        #expect(DocsTokenizer.tokens("The Sensitivity Ratios are adjusted!") == ["sensitivity", "ratio", "adjust"])
        #expect(DocsTokenizer.tokens("Wie ändere ich meine Basalrate?") == ["andere", "basalrate"])
        #expect(DocsTokenizer.tokens("the Trio app") == [])
        #expect(DocsTokenizer.tokens("") == [])
    }

    @Test("Stemmer leaves short words and double-s words alone") func stemmer() {
        #expect(DocsTokenizer.stem("glass") == "glass")
        #expect(DocsTokenizer.stem("bolus") == "bolus")
        #expect(DocsTokenizer.stem("carbs") == "carb")
        #expect(DocsTokenizer.stem("entries") == "entry")
        #expect(DocsTokenizer.stem("looping") == "loop")
        #expect(DocsTokenizer.stem("is") == "is")
    }

    @Test("Query tokens map everyday and German wording to the documentation's terms") func querySynonyms() {
        #expect(DocsTokenizer.queryTokens("high blood sugar") == ["high", "blood", "glucose"])
        #expect(DocsTokenizer.queryTokens("Blutzucker Zielwert nachts") == ["glucose", "target", "night"])
        // Indexed text is never rewritten.
        #expect(DocsTokenizer.tokens("high blood sugar") == ["high", "blood", "sugar"])
    }

    // MARK: - Search

    @Test("Search ranks the passage about the queried topic first") func ranking() {
        let index = sampleIndex()

        #expect(index.search("How does the sensitivity ratio work?").first?.chunk.id == 0)
        #expect(index.search("enable SMB always").first?.chunk.id == 1)
        #expect(index.search("upload to nightscout").first?.chunk.id == 2)
    }

    @Test("Search ignores passages without a matching term and honours the limit") func limits() {
        let index = sampleIndex()

        #expect(index.search("ratio adjustment").map(\.chunk.id) == [0])
        #expect(index.search("xyzzy").isEmpty)
        #expect(index.search("trio glucose insulin", limit: 1).count == 1)
        #expect(index.search("ratio", limit: 0).isEmpty)
    }

    @Test("Passages whose titles match the question outrank passages that merely mention it") func titleBoost() {
        let index = DocsIndex(
            chunks: [
                DocsChunk(
                    id: 0,
                    location: "a/#summary",
                    page: "Insulin Sensitivities",
                    section: "Summary",
                    text: "ISF ISF ISF Dynamic ISF changes ISF. Dynamic ISF uses ISF."
                ),
                DocsChunk(
                    id: 1,
                    location: "b/#dynamic-isf",
                    page: "Dynamic Settings",
                    section: "Dynamic ISF",
                    text: "Dynamic ISF replaces the fixed sensitivity factor with one calculated from your total daily dose of insulin and your current glucose, so corrections adapt to how you respond."
                )
            ],
            baseURL: baseURL
        )

        #expect(index.search("What is Dynamic ISF?").first?.chunk.id == 1)
    }

    @Test("Generator weights scale the score and missing JSON fields fall back to defaults") func weights() throws {
        let json = Data("""
        {"id": 7, "location": "x/#y", "page": "P", "section": "S", "text": "autosens"}
        """.utf8)
        let plain = try JSONDecoder().decode(DocsChunk.self, from: json)
        #expect(plain.weight == 1)
        #expect(!plain.outdated)

        let damped = DocsChunk(id: 0, location: "m/#a", page: "Migrating", section: "Autosens", text: "autosens", weight: 0.5)
        let full = DocsChunk(id: 1, location: "a/#a", page: "Autosens", section: "Autosens", text: "autosens")
        let index = DocsIndex(chunks: [damped, full], baseURL: baseURL)
        #expect(index.search("autosens").map(\.chunk.id) == [1, 0])
    }

    @Test("Passage URLs point at the section on triodocs.org") func urls() {
        let index = sampleIndex()

        #expect(
            index.url(for: index.chunks[0])?.absoluteString ==
                "https://triodocs.org/configuration/settings/algorithm/autosens/#sensitivity-ratio"
        )
    }

    // MARK: - Prompt assembly

    @Test("Context selection keeps rank order, stays within budget and always keeps the best hit") func selection() {
        let long = DocsChunk(id: 0, location: "a/#a", page: "A", section: "A", text: String(repeating: "a", count: 100))
        let medium = DocsChunk(id: 1, location: "b/#b", page: "B", section: "B", text: String(repeating: "b", count: 90))
        let short = DocsChunk(id: 2, location: "c/#c", page: "C", section: "C", text: String(repeating: "c", count: 50))
        let hits = [long, medium, short].map { DocsSearchHit(chunk: $0, score: 1) }

        #expect(DocsAssistantPrompt.select(hits, budget: 10000).map(\.id) == [0, 1, 2])
        // 100 + 90 would exceed 150, 100 + 50 fits exactly.
        #expect(DocsAssistantPrompt.select(hits, budget: 150).map(\.id) == [0, 2])
        #expect(DocsAssistantPrompt.select(hits, budget: 1).map(\.id) == [0])
        #expect(DocsAssistantPrompt.select(hits, budget: 10000, maximumCount: 2).map(\.id) == [0, 1])
        #expect(DocsAssistantPrompt.select([], budget: 10000).isEmpty)
    }

    @Test("Context selection drops weak hits beyond the guaranteed minimum") func relevanceCutoff() {
        let index = sampleIndex()
        let chunks = index.chunks
        let hits = [
            DocsSearchHit(chunk: chunks[0], score: 10),
            DocsSearchHit(chunk: chunks[1], score: 1),
            DocsSearchHit(chunk: chunks[2], score: 1),
            DocsSearchHit(chunk: DocsChunk(id: 3, location: "d/#d", page: "D", section: "D", text: "d"), score: 1),
            DocsSearchHit(chunk: DocsChunk(id: 4, location: "e/#e", page: "E", section: "E", text: "e"), score: 6)
        ]

        // The first three are always taken; after that only hits scoring at least half of the best one.
        #expect(DocsAssistantPrompt.select(hits, budget: 10000).map(\.id) == [0, 1, 2, 4])
    }

    @Test("Prompt numbers the excerpts with their breadcrumb and ends with the question") func prompt() {
        let index = sampleIndex()
        let prompt = DocsAssistantPrompt.prompt(question: "What is autosens?", excerpts: [index.chunks[0], index.chunks[1]])

        #expect(prompt.hasPrefix("Documentation excerpts:"))
        #expect(prompt.contains("[1] Autosens › Sensitivity Ratio\nThe Sensitivity Ratio"))
        #expect(prompt.contains("[2] SMB Settings › Enable SMB Always"))
        #expect(prompt.hasSuffix("Question: What is autosens?"))

        let german = DocsAssistantPrompt.prompt(question: "Was ist Autosens?", excerpts: [], answerLanguage: "German")
        #expect(german.hasSuffix("Question: Was ist Autosens?\nAnswer in German."))

        let outdated = DocsChunk(id: 9, location: "n/#u", page: "Nightscout ✏️", section: "Upload", text: "Text.", outdated: true)
        let flagged = DocsAssistantPrompt.prompt(question: "Q?", excerpts: [outdated])
        #expect(
            flagged.contains("[1] Nightscout ✏️ › Upload (this page is marked as not yet updated for the current Trio version)")
        )
    }

    @Test("Search query combines the question with the model's translation and terms") func searchQuery() {
        let rewrite = DocsQueryRewrite(translation: "What is Autosens?", terms: ["Autosens", "Sensitivity Ratio"])
        #expect(
            DocsAssistantPrompt.searchQuery(question: "Was ist Autosens?", rewrite: rewrite) ==
                "Was ist Autosens? What is Autosens? Autosens Sensitivity Ratio"
        )
        #expect(DocsAssistantPrompt.searchQuery(question: "What is autosens?", rewrite: .none) == "What is autosens?")
    }

    @Test("Answer language is detected among the languages the model supports") func answerLanguage() {
        let supported: Set<String> = ["en", "de", "fr", "es", "zh-Hans"]

        #expect(
            DocsAssistantPrompt.answerLanguage(
                for: "Wie aktiviere ich SMB bei hohem Blutzucker?",
                supportedLanguageCodes: supported,
                deviceLanguageCode: "en"
            ) == "German"
        )
        #expect(
            DocsAssistantPrompt.answerLanguage(
                for: "How do I enable SMB with high glucose readings?",
                supportedLanguageCodes: supported,
                deviceLanguageCode: "de"
            ) == "English"
        )
        // Too short for a reliable guess, but with a supported device language there is always an answer.
        #expect(
            DocsAssistantPrompt.answerLanguage(for: "Max IOB", supportedLanguageCodes: supported, deviceLanguageCode: "de") != nil
        )
        #expect(DocsAssistantPrompt.languageCode(for: Locale.Language(identifier: "zh-Hant-TW")) == "zh-Hant")
        #expect(DocsAssistantPrompt.languageCode(for: Locale.Language(identifier: "pt-BR")) == "pt")
    }

    @Test("Uncertain language guesses fall back to the device language only when the model supports it") func languageFallback() {
        let supported: Set<String> = ["en", "de"]

        #expect(
            DocsAssistantPrompt
                .resolveLanguageCode(guess: ("de", 0.9), deviceLanguageCode: "en", supportedLanguageCodes: supported) == "de"
        )
        #expect(
            DocsAssistantPrompt
                .resolveLanguageCode(guess: ("fr", 0.2), deviceLanguageCode: "de", supportedLanguageCodes: supported) == "de"
        )
        #expect(
            DocsAssistantPrompt
                .resolveLanguageCode(guess: ("fr", 0.2), deviceLanguageCode: "xx", supportedLanguageCodes: supported) == nil
        )
        #expect(
            DocsAssistantPrompt
                .resolveLanguageCode(guess: nil, deviceLanguageCode: "en", supportedLanguageCodes: supported) == "en"
        )
        #expect(
            DocsAssistantPrompt
                .resolveLanguageCode(guess: nil, deviceLanguageCode: nil, supportedLanguageCodes: supported) == nil
        )
        #expect(
            DocsAssistantPrompt
                .resolveLanguageCode(guess: ("fr", 0.2), deviceLanguageCode: "xx", supportedLanguageCodes: []) == "xx"
        )
    }

    // MARK: - Bundled index

    @Test("Bundled index ships with the app and covers the documentation") func bundled() throws {
        let index = try DocsIndex.loadBundled()

        #expect(index.chunks.count > 500)
        #expect(index.baseURL.absoluteString == "https://triodocs.org/")
        #expect(index.chunks.allSatisfy { $0.text.count <= 1500 })

        let pages = Set(index.chunks.map { $0.location.split(separator: "#").first.map(String.init) ?? "" })
        #expect(pages.count > 50)

        let top = try #require(index.search("autosens sensitivity ratio").first)
        #expect(top.chunk.location.contains("autosens"))
        #expect(index.search("Enable SMB with high glucose").first?.chunk.location.contains("smb") == true)
    }

    @Test("Assistant status is a concrete value on every OS version") func status() {
        let status = DocsAssistantSupport.status

        if #available(iOS 26.0, *) {
            #expect(status != .unsupportedOS)
        } else {
            #expect(status == .unsupportedOS)
            #expect(!status.isOffered)
        }
    }
}
