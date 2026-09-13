import Foundation

/// A published Trio release and its notes, as returned by the GitHub releases API.
///
/// The same shape is written into the app bundle at build time by
/// `scripts/capture-release-notes.sh`, so the bundled fallback and a live fetch decode
/// through this one type.
struct ReleaseNotes: Codable, Equatable, Identifiable {
    /// Git tag of the release, for example `v0.8.4`.
    let tagName: String

    var id: String { tagName }

    /// Human readable release name, for example `Trio v0.8.4`.
    let name: String

    /// Full release body, in GitHub flavoured Markdown.
    let body: String

    /// Page to open for the complete notes.
    let htmlURL: String

    /// ISO-8601 publication timestamp. Empty when GitHub did not supply one.
    let publishedAt: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }

    /// Version without the leading `v`, for comparison against `CFBundleShortVersionString`.
    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    var url: URL? {
        URL(string: htmlURL)
    }

    /// Publication date, or `nil` when GitHub supplied none.
    var publishedDate: Date? {
        publishedAt.isEmpty ? nil : ISO8601DateFormatter().date(from: publishedAt)
    }

    /// Publication date formatted for display, empty when unavailable.
    var publishedDateString: String {
        guard let publishedDate else {
            return ""
        }
        return publishedDate.formatted(date: .abbreviated, time: .omitted)
    }
}

extension ReleaseNotes {
    /// Decoding for the bundled fallback file, which uses camelCase keys rather than the
    /// GitHub API's snake_case.
    private struct Bundled: Decodable {
        let tagName: String
        let name: String
        let body: String
        let htmlURL: String
        let publishedAt: String
    }

    /// Decodes the releases written into the app bundle at build time, newest first.
    ///
    /// - Parameter data: Contents of `BundledReleaseNotes.json`.
    static func decodeBundled(from data: Data) throws -> [ReleaseNotes] {
        try JSONDecoder().decode([Bundled].self, from: data).map {
            ReleaseNotes(
                tagName: $0.tagName,
                name: $0.name,
                body: $0.body,
                htmlURL: $0.htmlURL,
                publishedAt: $0.publishedAt
            )
        }
    }
}

// MARK: - Highlights

extension ReleaseNotes {
    /// A single bullet from the release's summary section.
    struct Highlight: Identifiable, Equatable {
        let id: Int

        /// The bolded lead-in, for example `MedtrumKit`. Empty when the bullet has none.
        let subject: String

        /// The rest of the bullet. Empty when the bullet is only a heading for nested ones.
        let detail: String

        /// Nesting depth, 0 for a top level bullet.
        let level: Int
    }

    /// A GitHub alert callout, for example `> [!IMPORTANT]`.
    ///
    /// These carry the "update immediately" style guidance that some releases lead with, so
    /// they are surfaced rather than dropped along with the rest of the Markdown.
    struct Callout: Identifiable, Equatable {
        enum Kind: String {
            case note = "NOTE"
            case tip = "TIP"
            case important = "IMPORTANT"
            case warning = "WARNING"
            case caution = "CAUTION"
        }

        let id: Int
        let kind: Kind
        let text: String
    }

    /// Heading that introduces the summary section in Trio's release notes.
    private static let highlightsHeading = "What's Changed At A Glance"

    /// Body split into trimmed lines.
    ///
    /// GitHub returns release bodies with CRLF endings. Splitting on the newlines character
    /// set would treat `\r` and `\n` as two separate breaks and yield a spurious blank line
    /// between every real one, which is enough to break multi-line parsing.
    private var bodyLines: [String] {
        rawBodyLines.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Body split into lines with leading whitespace intact, so nesting can be measured.
    private var rawBodyLines: [String] {
        body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    /// The bullets under "What's Changed At A Glance".
    ///
    /// Trio's release notes lead with that section, and the rest of the body is a long list
    /// of pull request links that is not worth rendering in a sheet - the "full release
    /// notes" link covers those. Returns an empty array when the section is absent, which is
    /// how a release with a different layout is detected.
    var highlights: [Highlight] {
        var result: [Highlight] = []
        var insideSection = false

        for rawLine in rawBodyLines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("#") {
                // A heading either opens the section we want or closes it again.
                let heading = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if heading.caseInsensitiveCompare(Self.highlightsHeading) == .orderedSame {
                    insideSection = true
                } else if insideSection {
                    break
                }
                continue
            }

            guard insideSection else {
                continue
            }

            // A horizontal rule closes the section too.
            if line == "---" || line == "***" {
                break
            }

            guard line.hasPrefix("- ") || line.hasPrefix("* ") else {
                continue
            }

            let bullet = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            guard !bullet.isEmpty else {
                continue
            }

            result.append(Self.parseBullet(bullet, id: result.count, level: Self.indentLevel(of: rawLine)))
        }

        return result
    }

    /// The release's opening prose, before the first section heading.
    ///
    /// Not every release uses the "What's Changed At A Glance" convention - hotfixes in
    /// particular lead straight into prose - so this gives the sheet something meaningful to
    /// show when `highlights` comes back empty.
    var summary: String {
        var paragraphs: [String] = []

        for line in bodyLines {
            // The title heading opens the body; any other heading ends the intro.
            if line.hasPrefix("##") {
                break
            }
            if line == "---" || line == "***" {
                break
            }
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(">") {
                continue
            }

            paragraphs.append(line)
        }

        return paragraphs.joined(separator: "\n\n")
    }

    /// GitHub alert callouts found anywhere in the release body.
    var callouts: [Callout] {
        var result: [Callout] = []
        var currentKind: Callout.Kind?
        var currentLines: [String] = []

        func flush() {
            defer {
                currentKind = nil
                currentLines = []
            }
            guard let kind = currentKind else {
                return
            }
            let text = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else {
                return
            }
            result.append(Callout(id: result.count, kind: kind, text: text))
        }

        for line in bodyLines {
            guard line.hasPrefix(">") else {
                flush()
                continue
            }

            let content = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)

            // `> [!IMPORTANT]` opens a new callout; following `>` lines are its body.
            if content.hasPrefix("[!"), let closing = content.firstIndex(of: "]") {
                flush()
                let marker = String(content[content.index(content.startIndex, offsetBy: 2) ..< closing])
                currentKind = Callout.Kind(rawValue: marker.uppercased())
                continue
            }

            if currentKind != nil, !content.isEmpty {
                currentLines.append(content)
            }
        }

        flush()
        return result
    }

    /// Nesting depth of a bullet, from its leading whitespace. Tabs count as one level.
    private static func indentLevel(of rawLine: String) -> Int {
        var spaces = 0
        for character in rawLine {
            if character == " " {
                spaces += 1
            } else if character == "\t" {
                spaces += 2
            } else {
                break
            }
        }
        return min(spaces / 2, 2)
    }

    /// Splits a bullet into its bolded lead-in and the remaining text.
    ///
    /// Trio writes these as `**Subject** — detail`. Anything that does not follow that shape
    /// is kept whole as the detail, so an unexpected format degrades to plain text rather
    /// than being dropped.
    private static func parseBullet(_ bullet: String, id: Int, level: Int) -> Highlight {
        guard bullet.hasPrefix("**"),
              let closing = bullet.range(of: "**", range: bullet.index(bullet.startIndex, offsetBy: 2) ..< bullet.endIndex)
        else {
            return Highlight(id: id, subject: "", detail: bullet, level: level)
        }

        let subject = String(bullet[bullet.index(bullet.startIndex, offsetBy: 2) ..< closing.lowerBound])
        var detail = String(bullet[closing.upperBound...]).trimmingCharacters(in: .whitespaces)

        // Drop the separator Trio uses between subject and detail.
        for separator in ["—", "-", "–", ":"] where detail.hasPrefix(separator) {
            detail = String(detail.dropFirst(separator.count)).trimmingCharacters(in: .whitespaces)
            break
        }

        // A bold bullet with no detail introduces the nested bullets beneath it, so the
        // subject stays as the subject and keeps its emphasis.
        return Highlight(
            id: id,
            subject: subject.trimmingCharacters(in: CharacterSet(charactersIn: ":")),
            detail: detail,
            level: level
        )
    }
}
