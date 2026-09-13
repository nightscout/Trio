import Foundation

/// Supplies the release notes for the version of Trio that is installed, and remembers whether
/// the user has already seen them.
///
/// Notes come from three places, in order of preference:
///
/// 1. A live fetch from the GitHub releases API, because notes are sometimes edited after a
///    release is published.
/// 2. The copy cached from the last successful fetch.
/// 3. The copy bundled at build time by `scripts/capture-release-notes.sh`, so a phone that has
///    never been online still has something to show.
///
/// The release is looked up by exact tag, so Trio only ever shows notes for the version actually
/// installed - never for a newer release the user has not built.
@MainActor final class ReleaseNotesService: ObservableObject {
    static let shared = ReleaseNotesService()

    private init() {}

    // MARK: - Constants

    private static let repository = "nightscout/Trio"

    /// How long a successful fetch is trusted before another one is attempted.
    private static let refreshInterval: TimeInterval = 86400 // 24 hours

    private static let bundledResourceName = "BundledReleaseNotes"

    /// Oldest release worth showing. Earlier notes describe an app far enough removed from the
    /// current one that they are more confusing than useful.
    private static let minimumVersion = [0, 8, 0]

    // MARK: - Persisted State

    /// Releases from the last successful fetch, newest first.
    @Persisted(key: "cachedReleaseList") private var cachedReleases: [ReleaseNotes]? = nil

    /// When `cachedNotes` was fetched.
    @Persisted(key: "releaseNotesLastFetched") private var lastFetched: Date? = .distantPast

    /// Version whose notes the user has dismissed, for example `0.8.4`.
    ///
    /// Stored rather than a plain flag so that installing a newer release surfaces the panel
    /// again without anything having to reset it.
    @Persisted(key: "acknowledgedReleaseNotesVersion") private var acknowledgedVersion: String? = nil

    // MARK: - Published State

    /// Stable releases up to and including this build's version, newest first.
    @Published private(set) var releases: [ReleaseNotes] = []

    /// Notes matching this build's version. `nil` when none could be found.
    var notes: ReleaseNotes? {
        releases.first { $0.version == installedVersion }
    }

    /// Every release older than this build's, newest first.
    var previousReleases: [ReleaseNotes] {
        guard let notes else {
            return releases
        }
        return releases.filter { $0.version != notes.version }
    }

    // MARK: - Derived State

    /// The installed marketing version, for example `0.8.4`.
    ///
    /// Development builds carry a four-part `AppDevVersion` as well, but their
    /// `CFBundleShortVersionString` still matches the release they were branched from, which is
    /// the release whose notes apply.
    var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// Whether the Home panel should offer the notes.
    var hasUnacknowledgedNotes: Bool {
        guard let notes else {
            return false
        }
        return acknowledgedVersion != notes.version
    }

    // MARK: - Public Methods

    /// Resolves the notes for the installed version, preferring fresh content.
    ///
    /// Safe to call repeatedly; the network is only touched once per `refreshInterval`.
    func load() async {
        // Show whatever is already available first, so nothing waits on the network.
        releases = Self.supported(resolveOffline())

        guard shouldRefresh else {
            return
        }

        let fetched = Self.supported(await fetchReleases())
        guard !fetched.isEmpty else {
            return
        }

        cachedReleases = fetched
        lastFetched = Date()
        releases = fetched
    }

    /// Marks the installed version's notes as seen, which removes the Home panel entry.
    ///
    /// The notes stay reachable from Settings afterwards.
    func acknowledge() {
        guard let notes else {
            return
        }
        acknowledgedVersion = notes.version
        objectWillChange.send()
    }

    // MARK: - Private Methods

    private var shouldRefresh: Bool {
        Date().timeIntervalSince(lastFetched ?? .distantPast) > Self.refreshInterval
    }

    /// Best available releases without touching the network.
    private func resolveOffline() -> [ReleaseNotes] {
        if let cachedReleases, !cachedReleases.isEmpty {
            return cachedReleases
        }
        return loadBundled()
    }

    /// Reads the releases written into the app bundle at build time.
    private func loadBundled() -> [ReleaseNotes] {
        guard let url = Bundle.main.url(forResource: Self.bundledResourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            return []
        }

        do {
            return try ReleaseNotes.decodeBundled(from: data)
        } catch {
            debug(.default, "Failed to decode bundled release notes: \(error)")
            return []
        }
    }

    /// Fetches published releases, keeping the stable ones this build has reached.
    ///
    /// Prereleases and drafts are dropped, as is anything newer than the installed version, so
    /// the list never advertises notes for a release the user is not running yet. Returns an
    /// empty array on any failure.
    private func fetchReleases() async -> [ReleaseNotes] {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases?per_page=100") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                debug(.default, "Release list fetch returned status \(status)")
                return []
            }

            let installed = Self.versionComponents(installedVersion)

            return try JSONDecoder().decode([GitHubRelease].self, from: data)
                .filter { !$0.draft && !$0.prerelease }
                .map(\.notes)
                .filter {
                    installed.isEmpty || Self.versionComponents($0.version).lexicographicallyPrecedes(installed) || $0
                        .version == installedVersion }
                .sorted { Self.versionComponents($1.version).lexicographicallyPrecedes(Self.versionComponents($0.version)) }
        } catch {
            debug(.default, "Failed to fetch release list: \(error)")
            return []
        }
    }

    /// Drops releases older than `minimumVersion`.
    private static func supported(_ releases: [ReleaseNotes]) -> [ReleaseNotes] {
        releases.filter { release in
            let components = versionComponents(release.version)
            return !components.isEmpty && !components.lexicographicallyPrecedes(minimumVersion)
        }
    }

    /// Numeric components of a version, for ordering. Empty when it is not dotted numerals.
    private static func versionComponents(_ version: String) -> [Int] {
        let pieces = version.split(separator: ".").map { Int($0) }
        guard !pieces.isEmpty, !pieces.contains(nil) else {
            return []
        }
        return pieces.compactMap { $0 }
    }
}

// MARK: - GitHub payload

/// Release as returned by the list endpoint, which carries fields the app does not keep.
private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: String
    let publishedAt: String?
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case draft
        case prerelease
    }

    var notes: ReleaseNotes {
        ReleaseNotes(
            tagName: tagName,
            name: name ?? tagName,
            body: body ?? "",
            htmlURL: htmlURL,
            publishedAt: publishedAt ?? ""
        )
    }
}
