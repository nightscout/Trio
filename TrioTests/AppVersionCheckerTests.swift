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

    @Test("An entry with nothing to match on matches nothing") func emptyEntryMatchesNothing() {
        #expect(!Self.matches(Entry(version: ""), "1.0", "main", "0123456"))
        #expect(!Self.matches(Entry(version: " ", branch: "", sha: "  ", message: "x"), "1.0", "main", "0123456"))
        #expect(!Self.matches(Entry(version: ""), "", nil, nil))
    }

    @Test("Earlier builds decode empty-version entries and never match them") func legacyIgnoresEmptyVersion() {
        let json = """
        {
            "blacklistedVersions": [
                { "version": "0.5.0" },
                { "version": "", "sha": "0123456" },
                { "version": "", "branch": "dev", "message": "x" }
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
