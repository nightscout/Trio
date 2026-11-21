import Foundation
import Testing
@testable import Trio

/// Covers the blacklist format read by `AppVersionChecker`, including the guarantee that builds
/// released before entries could name a branch and commit still read the file correctly.
@Suite("AppVersionChecker blacklist") @MainActor struct AppVersionCheckerTests {
    // MARK: - The decoder shipped in earlier builds

    /// Exact copy of the models in builds released before `branch` / `sha` were added.
    /// Those builds run `try? JSONDecoder().decode(LegacyBlacklist.self, from: data)` and check
    /// `.blacklistedVersions.map(\.version).contains(currentVersion)`. Do not change these.
    private struct LegacyBlacklist: Decodable {
        let blacklistedVersions: [LegacyVersionEntry]
    }

    private struct LegacyVersionEntry: Decodable {
        let version: String
    }

    private static func legacyIsBlacklisted(_ json: String, version: String) -> Bool {
        (try? JSONDecoder().decode(LegacyBlacklist.self, from: Data(json.utf8)))?
            .blacklistedVersions
            .map(\.version)
            .contains(version) ?? false
    }

    private static func decode(_ json: String) throws -> [AppVersionChecker.VersionEntry] {
        try JSONDecoder().decode(AppVersionChecker.Blacklist.self, from: Data(json.utf8)).blacklistedVersions
    }

    private static let mixedJSON = """
    {
        "blacklistedVersions": [
            { "version": "0.5.0" },
            { "version": "0.6.0.12", "branch": "dev", "sha": "a1b2c3d", "message": "Rebuild from dev." },
            { "version": "0.6.0.13", "sha": "0123456789abcdef0123456789abcdef01234567" }
        ]
    }
    """

    // MARK: - Backward compatibility

    @Test("Earlier builds still decode entries that carry branch and sha") func legacyDecodesExtraFields() throws {
        let legacy = try JSONDecoder().decode(LegacyBlacklist.self, from: Data(Self.mixedJSON.utf8))
        #expect(legacy.blacklistedVersions.map(\.version) == ["0.5.0", "0.6.0.12", "0.6.0.13"])
        #expect(Self.legacyIsBlacklisted(Self.mixedJSON, version: "0.5.0"))
        #expect(Self.legacyIsBlacklisted(Self.mixedJSON, version: "0.6.0.12"))
        #expect(!Self.legacyIsBlacklisted(Self.mixedJSON, version: "0.8.0"))
    }

    @Test("Earlier builds ignore unknown top-level keys") func legacyIgnoresTopLevelKeys() {
        let json = """
        { "schemaVersion": 2, "notes": "x", "blacklistedVersions": [ { "version": "0.5.0", "reason": "y" } ] }
        """
        #expect(Self.legacyIsBlacklisted(json, version: "0.5.0"))
    }

    /// Documents why `version` must stay on every entry: without it the old decode throws and
    /// earlier builds lose the whole blacklist, not just that entry.
    @Test("An entry without a version breaks the whole list for earlier builds") func legacyNeedsVersion() {
        let json = """
        { "blacklistedVersions": [ { "version": "0.5.0" }, { "branch": "dev", "sha": "a1b2c3d" } ] }
        """
        #expect(!Self.legacyIsBlacklisted(json, version: "0.5.0"))
    }

    @Test("The published blacklisted-versions.json is readable by earlier builds")
    func repositoryFileIsLegacyCompatible() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TrioTests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("blacklisted-versions.json")
        let data = try Data(contentsOf: url)

        let legacy = try JSONDecoder().decode(LegacyBlacklist.self, from: data)
        let current = try JSONDecoder().decode(AppVersionChecker.Blacklist.self, from: data)
        #expect(!legacy.blacklistedVersions.isEmpty)
        #expect(current.blacklistedVersions.map(\.version) == legacy.blacklistedVersions.map(\.version))
    }

    // MARK: - Decoding

    @Test("Current builds decode branch, sha and message") func decodesBranchSHAAndMessage() throws {
        let entries = try Self.decode(Self.mixedJSON)
        let expected: [AppVersionChecker.VersionEntry] = [
            .init(version: "0.5.0"),
            .init(version: "0.6.0.12", branch: "dev", sha: "a1b2c3d", message: "Rebuild from dev."),
            .init(version: "0.6.0.13", sha: "0123456789abcdef0123456789abcdef01234567")
        ]
        #expect(entries == expected)
    }

    @Test("A malformed entry is skipped instead of dropping the list") func skipsMalformedEntries() throws {
        let json = """
        { "blacklistedVersions": [ { "version": "0.5.0" }, { "sha": 12 }, "junk", 7, { "version": "0.6.0" } ] }
        """
        let entries = try Self.decode(json)
        #expect(entries.map(\.version) == ["0.5.0", "0.6.0"])
    }

    // MARK: - Matching

    @Test("A version-only entry matches every build of that version") func versionOnlyMatchesAll() {
        let entries = [AppVersionChecker.VersionEntry(version: "0.5.0")]
        #expect(AppVersionChecker.isBlacklisted(entries: entries, version: "0.5.0", branch: "main", sha: "abcdef0"))
        #expect(AppVersionChecker.isBlacklisted(entries: entries, version: "0.5.0", branch: nil, sha: nil))
        #expect(!AppVersionChecker.isBlacklisted(entries: entries, version: "0.5.1", branch: "main", sha: "abcdef0"))
    }

    @Test("Branch narrows the match") func branchNarrows() {
        let entries = [AppVersionChecker.VersionEntry(version: "0.6.0.12", branch: "dev")]
        #expect(AppVersionChecker.isBlacklisted(entries: entries, version: "0.6.0.12", branch: "dev", sha: "abcdef0"))
        #expect(!AppVersionChecker.isBlacklisted(entries: entries, version: "0.6.0.12", branch: "main", sha: "abcdef0"))
        #expect(!AppVersionChecker.isBlacklisted(entries: entries, version: "0.6.0.12", branch: nil, sha: "abcdef0"))
    }

    @Test("SHA matches by prefix in either direction, ignoring case") func shaPrefixMatch() {
        let full = "0123456789abcdef0123456789abcdef01234567"
        let fullEntry = [AppVersionChecker.VersionEntry(version: "1.0", sha: full)]
        let shortEntry = [AppVersionChecker.VersionEntry(version: "1.0", sha: "0123456")]

        #expect(AppVersionChecker.isBlacklisted(entries: fullEntry, version: "1.0", branch: "dev", sha: "0123456"))
        #expect(AppVersionChecker.isBlacklisted(entries: fullEntry, version: "1.0", branch: "dev", sha: "0123456789"))
        #expect(AppVersionChecker.isBlacklisted(entries: shortEntry, version: "1.0", branch: "dev", sha: full))
        #expect(AppVersionChecker.isBlacklisted(entries: shortEntry, version: "1.0", branch: "dev", sha: "0123456".uppercased()))
        #expect(!AppVersionChecker.isBlacklisted(entries: shortEntry, version: "1.0", branch: "dev", sha: "0123457"))
        #expect(!AppVersionChecker.isBlacklisted(entries: shortEntry, version: "1.0", branch: "dev", sha: nil))
        #expect(!AppVersionChecker.isBlacklisted(entries: shortEntry, version: "1.1", branch: "dev", sha: "0123456"))
    }

    @Test("SHAs shorter than seven characters never match") func shaTooShort() {
        let entries = [AppVersionChecker.VersionEntry(version: "1.0", sha: "0123")]
        #expect(!AppVersionChecker.isBlacklisted(entries: entries, version: "1.0", branch: "dev", sha: "0123456"))
        let full = [AppVersionChecker.VersionEntry(version: "1.0", sha: "0123456")]
        #expect(!AppVersionChecker.isBlacklisted(entries: full, version: "1.0", branch: "dev", sha: "0123"))
    }

    @Test("Empty branch or sha in an entry is treated as absent") func emptyFieldsIgnored() {
        let entries = [AppVersionChecker.VersionEntry(version: "1.0", branch: "", sha: "  ")]
        #expect(AppVersionChecker.isBlacklisted(entries: entries, version: "1.0", branch: "main", sha: "abcdef0"))
    }

    // MARK: - Supported combinations

    private typealias Entry = AppVersionChecker.VersionEntry

    private static func matches(_ entry: Entry, _ version: String, _ branch: String?, _ sha: String?) -> Bool {
        AppVersionChecker.isBlacklisted(entries: [entry], version: version, branch: branch, sha: sha)
    }

    @Test("1. Version only") func versionOnly() {
        let entry = Entry(version: "1.0")
        #expect(Self.matches(entry, "1.0", "main", "0123456"))
        #expect(Self.matches(entry, "1.0", "dev", "fedcba9"))
        #expect(!Self.matches(entry, "1.1", "main", "0123456"))
    }

    @Test("2. Empty version plus sha matches that commit at any version") func emptyVersionPlusSHA() {
        let entry = Entry(version: "", sha: "0123456")
        #expect(Self.matches(entry, "1.0", "main", "0123456"))
        #expect(Self.matches(entry, "2.3.4", "dev", "0123456789abcdef"))
        #expect(!Self.matches(entry, "1.0", "main", "fedcba9"))
        #expect(!Self.matches(entry, "1.0", "main", nil))
    }

    @Test("3. Version plus branch") func versionPlusBranch() {
        let entry = Entry(version: "1.0", branch: "dev")
        #expect(Self.matches(entry, "1.0", "dev", "0123456"))
        #expect(!Self.matches(entry, "1.0", "main", "0123456"))
        #expect(!Self.matches(entry, "1.1", "dev", "0123456"))
    }

    @Test("4. Empty version plus branch matches that branch at any version") func emptyVersionPlusBranch() {
        let entry = Entry(version: "", branch: "feat/x")
        #expect(Self.matches(entry, "1.0", "feat/x", "0123456"))
        #expect(Self.matches(entry, "9.9", "feat/x", nil))
        #expect(!Self.matches(entry, "1.0", "dev", "0123456"))
        #expect(!Self.matches(entry, "1.0", nil, "0123456"))
    }

    @Test("5. Version plus sha") func versionPlusSHA() {
        let entry = Entry(version: "1.0", sha: "0123456")
        #expect(Self.matches(entry, "1.0", "dev", "0123456"))
        #expect(!Self.matches(entry, "1.1", "dev", "0123456"))
        #expect(!Self.matches(entry, "1.0", "dev", "fedcba9"))
    }

    @Test("6. Version plus branch and sha") func versionPlusBranchAndSHA() {
        let entry = Entry(version: "1.0", branch: "dev", sha: "0123456")
        #expect(Self.matches(entry, "1.0", "dev", "0123456"))
        #expect(!Self.matches(entry, "1.1", "dev", "0123456"))
        #expect(!Self.matches(entry, "1.0", "main", "0123456"))
        #expect(!Self.matches(entry, "1.0", "dev", "fedcba9"))
    }

    @Test("Empty version plus branch and sha requires both") func emptyVersionPlusBranchAndSHA() {
        let entry = Entry(version: "", branch: "dev", sha: "0123456")
        #expect(Self.matches(entry, "1.0", "dev", "0123456"))
        #expect(!Self.matches(entry, "1.0", "main", "0123456"))
        #expect(!Self.matches(entry, "1.0", "dev", "fedcba9"))
    }

    @Test("\"SKIP\" means the same as empty in any match field") func skipSentinel() {
        let skipVersion = Entry(version: "SKIP", sha: "0123456")
        #expect(Self.matches(skipVersion, "1.0", "main", "0123456"))
        #expect(Self.matches(skipVersion, "2.0", "dev", "0123456"))
        #expect(!Self.matches(skipVersion, "1.0", "main", "fedcba9"))

        let skipVersionBranch = Entry(version: " SKIP ", branch: "feat/x")
        #expect(Self.matches(skipVersionBranch, "1.0", "feat/x", nil))
        #expect(!Self.matches(skipVersionBranch, "1.0", "dev", nil))

        let skipBranchAndSHA = Entry(version: "1.0", branch: "SKIP", sha: "SKIP")
        #expect(Self.matches(skipBranchAndSHA, "1.0", "main", "0123456"))
        #expect(!Self.matches(skipBranchAndSHA, "1.1", "main", "0123456"))
    }

    @Test("Only the exact uppercase sentinel skips") func skipIsCaseSensitive() {
        #expect(!Self.matches(Entry(version: "skip", branch: "dev"), "1.0", "dev", nil))
        #expect(Self.matches(Entry(version: "1.0", branch: "Skip"), "1.0", "Skip", nil))
        #expect(!Self.matches(Entry(version: "1.0", branch: "Skip"), "1.0", "dev", nil))
    }

    @Test("An entry made only of SKIP matches nothing") func allSkipMatchesNothing() {
        #expect(!Self.matches(Entry(version: "SKIP", branch: "SKIP", sha: "SKIP"), "1.0", "main", "0123456"))
        #expect(!Self.matches(Entry(version: "SKIP"), "SKIP", "SKIP", "SKIP"))
    }

    @Test("An entry with nothing to match on matches nothing") func emptyEntryMatchesNothing() {
        #expect(!Self.matches(Entry(version: ""), "1.0", "main", "0123456"))
        #expect(!Self.matches(Entry(version: " ", branch: "", sha: "  ", message: "x"), "1.0", "main", "0123456"))
        #expect(!Self.matches(Entry(version: ""), "", nil, nil))
    }

    @Test("Earlier builds decode empty and SKIP version entries and never match them") func legacyIgnoresEmptyVersion() {
        let json = """
        {
            "blacklistedVersions": [
                { "version": "0.5.0" },
                { "version": "", "sha": "0123456" },
                { "version": "", "branch": "dev", "message": "x" },
                { "version": "SKIP", "sha": "fedcba9" }
            ]
        }
        """
        #expect(Self.legacyIsBlacklisted(json, version: "0.5.0"))
        #expect(!Self.legacyIsBlacklisted(json, version: "1.0"))
    }

    // MARK: - Message

    @Test("The first matching entry with a message supplies it") func messageFromMatchingEntry() {
        let entries = [
            AppVersionChecker.VersionEntry(version: "1.0", sha: "9999999", message: "Other commit."),
            AppVersionChecker.VersionEntry(version: "1.0"),
            AppVersionChecker.VersionEntry(version: "1.0", branch: "dev", message: "  Dev build issue.  "),
            AppVersionChecker.VersionEntry(version: "1.0", message: "Later message.")
        ]
        let status = AppVersionChecker.blacklistStatus(entries: entries, version: "1.0", branch: "dev", sha: "0123456")
        #expect(status.isBlacklisted)
        #expect(status.message == "Dev build issue.")
    }

    @Test("No message when the matching entries have none") func noMessage() {
        let entries = [
            AppVersionChecker.VersionEntry(version: "1.0", message: " "),
            AppVersionChecker.VersionEntry(version: "2.0", message: "Not this build.")
        ]
        let status = AppVersionChecker.blacklistStatus(entries: entries, version: "1.0", branch: "main", sha: "0123456")
        #expect(status.isBlacklisted)
        #expect(status.message == nil)
        #expect(AppVersionChecker.blacklistStatus(entries: entries, version: "3.0", branch: "main", sha: nil).message == nil)
    }

    @Test("The alert keeps the standard text and appends the message") func alertText() {
        let standard = AppVersionChecker.blacklistAlertMessage(entryMessage: nil)
        #expect(!standard.isEmpty)
        #expect(AppVersionChecker.blacklistAlertMessage(entryMessage: "  ") == standard)
        #expect(AppVersionChecker.blacklistAlertMessage(entryMessage: "Update now.") == standard + "\n\nUpdate now.")
    }
}

// MARK: - Full fixture

/// One blacklist file exercising every supported entry shape, checked against many fake builds.
///
/// Each entry's `message` starts with a unique label ("A", "B", ...) so a test can tell exactly
/// which entries fired. Entries are listed in file order, which decides whose message is shown
/// when several match.
enum BlacklistFixture {
    static let json = """
    {
        "schemaVersion": 2,
        "notes": "Unknown top-level keys must be ignored by every build.",
        "blacklistedVersions": [
            { "version": "0.5.0", "message": "A: every 0.5.0 build" },
            { "version": "", "sha": "a1b2c3d", "message": "B: commit a1b2c3d, any version" },
            {
                "version": "SKIP",
                "sha": "0123456789abcdef0123456789abcdef01234567",
                "message": "C: full-length sha, any version"
            },
            { "version": "0.6.0.12", "branch": "dev", "message": "D: 0.6.0.12 from dev" },
            { "version": "", "branch": "feat/broken", "message": "E: every build from feat/broken" },
            { "version": "SKIP", "branch": "feat/also-broken", "message": "F: every build from feat/also-broken" },
            { "version": "0.7.0", "sha": "b2c3d4e", "message": "G: 0.7.0 at b2c3d4e", "reason": "extra key" },
            { "version": "0.8.0", "branch": "dev", "sha": "c3d4e5f", "message": "H: 0.8.0 from dev at c3d4e5f" },
            { "version": "0.9.0", "branch": "SKIP", "sha": "SKIP", "message": "I: every 0.9.0 build" },
            { "version": "", "branch": "dev", "sha": "d4e5f6a", "message": "L: dev at d4e5f6a, any version" },
            { "version": "0.5.0", "branch": "release/x", "message": "M: 0.5.0 from release/x" },
            { "version": "", "branch": "", "sha": "", "message": "X: nothing specified, never fires" },
            { "version": "SKIP", "branch": "SKIP", "sha": "SKIP", "message": "Y: all SKIP, never fires" },
            { "version": "  ", "branch": " SKIP ", "message": "Z: whitespace and SKIP, never fires" }
        ]
    }
    """

    struct Scenario: Sendable, CustomTestStringConvertible {
        let version: String
        let branch: String?
        let sha: String?
        /// Labels of the entries that must fire, in file order. Empty means not blacklisted.
        let fires: [String]
        /// Whether a build released before branch/sha support (version-only matching) would fire.
        let legacyFires: Bool
        let note: String

        var testDescription: String {
            "\(note) [\(version) \(branch ?? "nil") \(sha ?? "nil")]"
        }
    }

    static let scenarios: [Scenario] = [
        // Case 1: version only
        .init(version: "0.5.0", branch: "main", sha: "1111111", fires: ["A"], legacyFires: true, note: "version-only hit"),
        .init(version: "0.5.0", branch: nil, sha: nil, fires: ["A"], legacyFires: true, note: "version-only, no build details"),
        .init(version: "0.5.1", branch: "main", sha: "1111111", fires: [], legacyFires: false, note: "next patch version"),
        .init(version: "0.5", branch: "main", sha: "1111111", fires: [], legacyFires: false, note: "version is a prefix"),
        .init(version: "0.5.0.1", branch: "main", sha: "1111111", fires: [], legacyFires: false, note: "version extends entry"),
        .init(version: "0.9.0", branch: "main", sha: "9999999", fires: ["I"], legacyFires: true, note: "branch and sha SKIP"),
        .init(version: "0.9.0", branch: nil, sha: nil, fires: ["I"], legacyFires: true, note: "SKIP fields, no details"),

        // Overlapping entries: both fire, the first one's message is shown
        .init(version: "0.5.0", branch: "release/x", sha: "1111111", fires: ["A", "M"], legacyFires: true, note: "two entries"),

        // Case 2: empty / SKIP version plus sha
        .init(version: "1.0.0", branch: "main", sha: "a1b2c3d", fires: ["B"], legacyFires: false, note: "sha, any version"),
        .init(version: "1.0.0", branch: "dev", sha: "A1B2C3D", fires: ["B"], legacyFires: false, note: "sha upper case"),
        .init(version: "1.0.0", branch: "dev", sha: "a1b2c3d4e5", fires: ["B"], legacyFires: false, note: "longer build sha"),
        .init(version: "1.0.0", branch: "dev", sha: "a1b2c3e", fires: [], legacyFires: false, note: "sha off by one"),
        .init(version: "1.0.0", branch: "dev", sha: "a1b2c3", fires: [], legacyFires: false, note: "build sha too short"),
        .init(version: "1.0.0", branch: "dev", sha: "0a1b2c3d", fires: [], legacyFires: false, note: "sha not a prefix"),
        .init(version: "1.0.0", branch: "dev", sha: nil, fires: [], legacyFires: false, note: "build has no sha"),
        .init(version: "2.0.0", branch: "main", sha: "0123456", fires: ["C"], legacyFires: false, note: "short sha vs full"),
        .init(
            version: "2.0.0", branch: "main", sha: "0123456789abcdef0123456789abcdef01234567",
            fires: ["C"], legacyFires: false, note: "full sha vs full"
        ),
        .init(
            version: "2.0.0", branch: "main", sha: "0123456789abcdef0123456789abcdef01234568",
            fires: [], legacyFires: false, note: "full sha, last char differs"
        ),

        // Case 3: version plus branch
        .init(version: "0.6.0.12", branch: "dev", sha: "1111111", fires: ["D"], legacyFires: true, note: "version+branch hit"),
        .init(version: "0.6.0.12", branch: "main", sha: "1111111", fires: [], legacyFires: true, note: "other branch"),
        .init(version: "0.6.0.12", branch: "Dev", sha: "1111111", fires: [], legacyFires: true, note: "branch case differs"),
        .init(version: "0.6.0.12", branch: nil, sha: nil, fires: [], legacyFires: true, note: "build has no branch"),
        .init(version: "0.6.0.13", branch: "dev", sha: "1111111", fires: [], legacyFires: false, note: "other version"),

        // Case 4: empty / SKIP version plus branch
        .init(version: "3.1.0", branch: "feat/broken", sha: "1111111", fires: ["E"], legacyFires: false, note: "branch hit"),
        .init(version: "0.0.1", branch: "feat/broken", sha: nil, fires: ["E"], legacyFires: false, note: "branch, any version"),
        .init(version: "3.1.0", branch: "feat/broken-fix", sha: "1111111", fires: [], legacyFires: false, note: "branch prefix"),
        .init(version: "3.1.0", branch: "Feat/Broken", sha: "1111111", fires: [], legacyFires: false, note: "branch case"),
        .init(version: "3.1.0", branch: "feat/also-broken", sha: nil, fires: ["F"], legacyFires: false, note: "SKIP version"),

        // Case 5: version plus sha
        .init(version: "0.7.0", branch: "main", sha: "b2c3d4e", fires: ["G"], legacyFires: true, note: "version+sha hit"),
        .init(version: "0.7.0", branch: "main", sha: "1111111", fires: [], legacyFires: true, note: "other commit"),
        .init(version: "0.7.1", branch: "main", sha: "b2c3d4e", fires: [], legacyFires: false, note: "other version"),

        // Case 6: version plus branch and sha
        .init(version: "0.8.0", branch: "dev", sha: "c3d4e5f", fires: ["H"], legacyFires: true, note: "all three hit"),
        .init(version: "0.8.0", branch: "main", sha: "c3d4e5f", fires: [], legacyFires: true, note: "branch differs"),
        .init(version: "0.8.0", branch: "dev", sha: "1111111", fires: [], legacyFires: true, note: "sha differs"),
        .init(version: "0.8.1", branch: "dev", sha: "c3d4e5f", fires: [], legacyFires: false, note: "version differs"),

        // Empty version plus branch and sha
        .init(version: "4.0.0", branch: "dev", sha: "d4e5f6a", fires: ["L"], legacyFires: false, note: "branch+sha hit"),
        .init(version: "0.8.0", branch: "dev", sha: "d4e5f6a", fires: ["L"], legacyFires: true, note: "L but not H"),
        .init(version: "4.0.0", branch: "main", sha: "d4e5f6a", fires: [], legacyFires: false, note: "branch differs"),
        .init(version: "4.0.0", branch: "dev", sha: "1111111", fires: [], legacyFires: false, note: "sha differs"),

        // Several shapes at once
        .init(
            version: "0.6.0.12", branch: "dev", sha: "a1b2c3d",
            fires: ["B", "D"], legacyFires: true, note: "sha and version+branch"
        ),
        .init(
            version: "0.5.0", branch: "feat/broken", sha: "a1b2c3d",
            fires: ["A", "B", "E"], legacyFires: true, note: "three shapes"
        ),

        // Clean builds
        .init(version: "1.0.2", branch: "main", sha: "fedcba9", fires: [], legacyFires: false, note: "release build"),
        .init(version: "1.1.0.3", branch: "dev", sha: "fedcba9", fires: [], legacyFires: false, note: "dev build"),
        .init(version: "Unknown", branch: nil, sha: nil, fires: [], legacyFires: false, note: "no version information")
    ]

    static func label(_ entry: AppVersionChecker.VersionEntry) -> String {
        String((entry.message ?? "?").prefix { $0 != ":" })
    }
}

/// Runs every scenario in `BlacklistFixture` through the current matcher and the decoder
/// shipped in earlier builds.
@Suite("AppVersionChecker blacklist fixture") @MainActor struct AppVersionCheckerFixtureTests {
    /// Same models as builds released before `branch` / `sha` / `message`. Do not change these.
    private struct LegacyBlacklist: Decodable {
        let blacklistedVersions: [LegacyVersionEntry]
    }

    private struct LegacyVersionEntry: Decodable {
        let version: String
    }

    private static func entries() throws -> [AppVersionChecker.VersionEntry] {
        try JSONDecoder().decode(AppVersionChecker.Blacklist.self, from: Data(BlacklistFixture.json.utf8))
            .blacklistedVersions
    }

    private static func legacyVersions() throws -> [String] {
        try JSONDecoder().decode(LegacyBlacklist.self, from: Data(BlacklistFixture.json.utf8))
            .blacklistedVersions.map(\.version)
    }

    @Test("Both decoders read every fixture entry") func decodesEveryEntry() throws {
        let current = try Self.entries()
        let legacy = try Self.legacyVersions()
        #expect(current.count == 14)
        #expect(legacy.count == current.count)
        #expect(current.map(\.version) == legacy)
    }

    @Test("Never-fire entries fire for no scenario") func neverFireEntries() throws {
        let entries = try Self.entries()
        let neverFire = entries.filter { ["X", "Y", "Z"].contains(BlacklistFixture.label($0)) }
        #expect(neverFire.count == 3)
        for scenario in BlacklistFixture.scenarios {
            for entry in neverFire {
                #expect(!entry.matches(version: scenario.version, branch: scenario.branch, sha: scenario.sha))
            }
        }
    }

    @Test("Every matching entry is reached by some scenario") func everyEntryIsExercised() throws {
        let entries = try Self.entries()
        let fired = Set(BlacklistFixture.scenarios.flatMap(\.fires))
        let labels = Set(entries.map(BlacklistFixture.label)).subtracting(["X", "Y", "Z"])
        #expect(labels == fired)
    }

    @Test("Exactly the expected entries fire", arguments: BlacklistFixture.scenarios)
    func scenario(_ scenario: BlacklistFixture.Scenario) throws {
        let entries = try Self.entries()

        let fired = entries
            .filter { $0.matches(version: scenario.version, branch: scenario.branch, sha: scenario.sha) }
            .map(BlacklistFixture.label)
        #expect(fired == scenario.fires)

        let status = AppVersionChecker.blacklistStatus(
            entries: entries,
            version: scenario.version,
            branch: scenario.branch,
            sha: scenario.sha
        )
        #expect(status.isBlacklisted == !scenario.fires.isEmpty)
        if let first = scenario.fires.first {
            #expect(status.message?.hasPrefix(first + ":") == true)
        } else {
            #expect(status.message == nil)
        }
    }

    @Test("Earlier builds fire only on the version string", arguments: BlacklistFixture.scenarios)
    func legacyScenario(_ scenario: BlacklistFixture.Scenario) throws {
        let legacyVersions = try Self.legacyVersions()
        #expect(legacyVersions.contains(scenario.version) == scenario.legacyFires)
    }
}
