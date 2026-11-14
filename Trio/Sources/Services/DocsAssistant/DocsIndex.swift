import Foundation

/// One searchable passage of the Trio documentation (https://triodocs.org).
///
/// Produced by `scripts/build-docs-index.py` and shipped in `Resources/json/docs/trio-docs-index.json`.
struct DocsChunk: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    /// Path relative to the docs site root including the section anchor,
    /// e.g. `configuration/settings/algorithm/autosens/#sensitivity-ratio`.
    let location: String
    /// Title of the page the passage belongs to.
    let page: String
    /// Heading of the section the passage was taken from.
    let section: String
    let text: String
    /// Relevance multiplier chosen by the generator, below 1 for pages that are mostly comparison tables.
    let weight: Double
    /// Whether the docs mark the page as not yet updated for the current Trio version.
    let outdated: Bool

    init(
        id: Int,
        location: String,
        page: String,
        section: String,
        text: String,
        weight: Double = 1,
        outdated: Bool = false
    ) {
        self.id = id
        self.location = location
        self.page = page
        self.section = section
        self.text = text
        self.weight = weight
        self.outdated = outdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        location = try container.decode(String.self, forKey: .location)
        page = try container.decode(String.self, forKey: .page)
        section = try container.decode(String.self, forKey: .section)
        text = try container.decode(String.self, forKey: .text)
        weight = try container.decodeIfPresent(Double.self, forKey: .weight) ?? 1
        outdated = try container.decodeIfPresent(Bool.self, forKey: .outdated) ?? false
    }
}

/// A passage matched by a search, with its BM25 relevance score.
struct DocsSearchHit: Identifiable, Hashable, Sendable {
    let chunk: DocsChunk
    let score: Double

    var id: Int { chunk.id }
}

/// Offline full-text index over the bundled Trio documentation.
///
/// Ranking uses BM25 over a light English tokenizer. The index is small (under a thousand passages),
/// so everything is held in memory and a search returns instantly. Page and section titles are indexed
/// with double weight, and a passage whose section title is largely covered by the query gets a further
/// boost, so that a question naming a setting finds the section about that setting.
final class DocsIndex: Sendable {
    /// Resource name of the bundled index, relative to the `json` folder reference.
    static let bundledResource = "json/docs/trio-docs-index"

    /// The index shipped with the app, or `nil` when the resource is missing or malformed.
    static let bundled: DocsIndex? = try? loadBundled()

    let chunks: [DocsChunk]
    let baseURL: URL
    /// ISO date on which the index was generated from the docs site.
    let generated: String

    private struct Posting: Sendable {
        let chunk: Int
        let frequency: Int
    }

    private struct File: Decodable {
        let version: Int
        let baseURL: String
        let generated: String
        let chunks: [DocsChunk]
    }

    private let postings: [String: [Posting]]
    private let lengths: [Int]
    private let averageLength: Double
    /// Search terms of each passage's section and page title, for the title-coverage boost.
    private let sectionTerms: [Set<String>]
    private let pageTerms: [Set<String>]

    private static let k1 = 1.2
    /// Length normalisation. Lower than the usual 0.75 because passages are already capped in size and
    /// the longer, explanatory sections are usually the ones worth reading.
    private static let b = 0.5
    /// Extra score share for a passage whose section title is fully covered by the query, and the smaller
    /// share for its page title.
    private static let sectionBoost = 0.5
    private static let pageBoost = 0.25

    init(chunks: [DocsChunk], baseURL: URL, generated: String = "") {
        self.chunks = chunks
        self.baseURL = baseURL
        self.generated = generated

        var postings = [String: [Posting]]()
        var lengths = [Int]()
        var sectionTerms = [Set<String>]()
        var pageTerms = [Set<String>]()
        lengths.reserveCapacity(chunks.count)
        sectionTerms.reserveCapacity(chunks.count)
        pageTerms.reserveCapacity(chunks.count)

        for (position, chunk) in chunks.enumerated() {
            let sectionTokens = DocsTokenizer.tokens(chunk.section)
            let pageTokens = DocsTokenizer.tokens(chunk.page)
            let titleTokens = pageTokens + sectionTokens
            let tokens = DocsTokenizer.tokens(chunk.text) + titleTokens + titleTokens
            lengths.append(tokens.count)
            sectionTerms.append(Set(sectionTokens))
            pageTerms.append(Set(pageTokens))

            var counts = [String: Int]()
            for token in tokens {
                counts[token, default: 0] += 1
            }
            for (token, count) in counts {
                postings[token, default: []].append(Posting(chunk: position, frequency: count))
            }
        }

        self.postings = postings
        self.lengths = lengths
        self.sectionTerms = sectionTerms
        self.pageTerms = pageTerms
        let total = lengths.reduce(0, +)
        averageLength = lengths.isEmpty ? 1 : max(1, Double(total) / Double(lengths.count))
    }

    convenience init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(File.self, from: data)
        guard let baseURL = URL(string: file.baseURL) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.init(chunks: file.chunks, baseURL: baseURL, generated: file.generated)
    }

    static func loadBundled(from bundle: Bundle = .main) throws -> DocsIndex {
        guard let url = bundle.url(forResource: bundledResource, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try DocsIndex(contentsOf: url)
    }

    /// The best matching passages for a free-text query, best first.
    func search(_ query: String, limit: Int = 8) -> [DocsSearchHit] {
        let terms = Set(DocsTokenizer.queryTokens(query))
        guard !terms.isEmpty, !chunks.isEmpty, limit > 0 else { return [] }

        let documentCount = Double(chunks.count)
        var scores = [Int: Double]()

        for term in terms {
            guard let list = postings[term] else { continue }
            let documentFrequency = Double(list.count)
            let idf = log(1 + (documentCount - documentFrequency + 0.5) / (documentFrequency + 0.5))

            for posting in list {
                let frequency = Double(posting.frequency)
                let lengthNorm = 1 - Self.b + Self.b * Double(lengths[posting.chunk]) / averageLength
                scores[posting.chunk, default: 0] += idf * (frequency * (Self.k1 + 1)) / (frequency + Self.k1 * lengthNorm)
            }
        }

        for (chunk, score) in scores {
            let boost = 1 + Self.sectionBoost * coverage(of: sectionTerms[chunk], by: terms)
                + Self.pageBoost * coverage(of: pageTerms[chunk], by: terms)
            scores[chunk] = score * chunks[chunk].weight * boost
        }

        return scores
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
            }
            .prefix(limit)
            .map { DocsSearchHit(chunk: chunks[$0.key], score: $0.value) }
    }

    /// Share of `title` terms that occur in `query`, 0 for an empty title.
    private func coverage(of title: Set<String>, by query: Set<String>) -> Double {
        title.isEmpty ? 0 : Double(title.intersection(query).count) / Double(title.count)
    }

    /// The web page (and section) a passage was taken from.
    func url(for chunk: DocsChunk) -> URL? {
        URL(string: chunk.location, relativeTo: baseURL)?.absoluteURL
    }
}

/// Splits text into lowercase, diacritic-free search terms without stop words, with a tiny English stemmer.
enum DocsTokenizer {
    static let stopwords: Set<String> = [
        // English, plus words that appear in nearly every passage of the docs
        "the", "a", "an", "and", "or", "of", "to", "in", "on", "for", "with", "is", "are", "was", "be",
        "it", "this", "that", "as", "at", "by", "from", "do", "does", "did", "how", "what", "when", "where",
        "which", "why", "can", "i", "my", "me", "you", "your", "we", "our", "if", "not", "no", "will", "should",
        "would", "there", "than", "then", "also", "into", "about", "any", "all", "get", "its", "they", "their",
        "trio", "app", "apps",
        // German, so that a German question still matches the English docs on the shared terms
        "der", "die", "das", "und", "oder", "ist", "ich", "mein", "meine", "wie", "was", "wenn", "ein", "eine",
        "einen", "im", "zu", "mit", "bei", "fur", "fuer", "auf", "nicht", "kann", "man", "es", "den", "dem", "des",
        "sich", "sind", "wird", "werden", "wo", "warum", "welche", "welcher", "welches", "bitte", "muss",
        "soll", "sollte", "machen", "mache", "habe", "hat", "haben"
    ]

    /// Words people type that the documentation spells differently, including the most common German terms.
    /// Applied to queries only (before stemming), never to the indexed text.
    static let querySynonyms: [String: String] = [
        "sugar": "glucose", "bg": "glucose", "bgs": "glucose", "blutzucker": "glucose", "zucker": "glucose",
        "pumpe": "pump", "insulinpumpe": "pump", "basalrate": "basal", "basalraten": "basal",
        "ziel": "target", "zielwert": "target", "zielbereich": "target", "temporares": "temp",
        "einstellung": "setting", "einstellungen": "settings", "benachrichtigung": "notification",
        "benachrichtigungen": "notifications", "alarme": "alarms", "kohlenhydrate": "carbs", "kh": "carbs",
        "mahlzeit": "meal", "mahlzeiten": "meals", "bolusrechner": "calculator", "uhr": "watch",
        "nacht": "night", "nachts": "night", "sport": "exercise", "bewegung": "exercise",
        "uberschreibung": "override", "empfindlichkeit": "sensitivity", "insulinempfindlichkeit": "sensitivity",
        "fernsteuerung": "remote", "aktivieren": "enable", "aktiviere": "enable", "einschalten": "enable",
        "ausschalten": "disable", "deaktivieren": "disable", "andern": "change", "andere": "change",
        "anleitung": "guide", "installieren": "install", "installation": "install", "bauen": "build"
    ]

    private static let separators = CharacterSet.alphanumerics.inverted

    static func tokens(_ text: String) -> [String] {
        tokens(text, synonyms: [:])
    }

    /// Like `tokens`, but with `querySynonyms` applied so that everyday and German wording finds the docs' terms.
    static func queryTokens(_ text: String) -> [String] {
        tokens(text, synonyms: querySynonyms)
    }

    private static func tokens(_ text: String, synonyms: [String: String]) -> [String] {
        let folded = text.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en")
        )
        return folded.components(separatedBy: separators).compactMap { word -> String? in
            let word = synonyms[word] ?? word
            guard word.count >= 2, !stopwords.contains(word) else { return nil }
            let stemmed = stem(word)
            return stemmed.count >= 2 ? stemmed : nil
        }
    }

    /// Strips the most common English suffixes so that "ratios", "ratio" and "adjusted", "adjust" match.
    static func stem(_ word: String) -> String {
        var stem = word
        if stem.hasSuffix("ies"), stem.count > 4 {
            stem = String(stem.dropLast(3)) + "y"
        } else if stem.hasSuffix("sses") {
            stem = String(stem.dropLast(2))
        } else if stem.hasSuffix("s"), !stem.hasSuffix("ss"), !stem.hasSuffix("us"), !stem.hasSuffix("is"), stem.count > 3 {
            stem.removeLast()
        }

        if stem.hasSuffix("ing"), stem.count > 5 {
            stem = String(stem.dropLast(3))
        } else if stem.hasSuffix("ed"), stem.count > 4 {
            stem = String(stem.dropLast(2))
        }
        return stem
    }
}
