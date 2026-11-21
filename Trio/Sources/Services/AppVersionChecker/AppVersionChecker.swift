import UIKit

// AppVersionChecker is a singleton responsible for checking the app's version status.
// It fetches version data from remote sources (GitHub), caches the results, and notifies the user
// if an update is available or if the current version is blacklisted.
@MainActor final class AppVersionChecker {
    // Shared singleton instance.
    static let shared = AppVersionChecker()

    // Private initializer to enforce the singleton pattern.
    private init() {}

    // MARK: - Persisted Properties

    // Cached app version for which data was last fetched.
    @Persisted(key: "cachedForVersion") private var cachedForVersion: String? = nil
    // The latest version fetched from GitHub.
    @Persisted(key: "latestVersion") private var persistedLatestVersion: String? = nil
    // The date when the latest version was checked.
    @Persisted(key: "latestVersionChecked") private var latestVersionChecked: Date? = .distantPast
    // Boolean flag indicating whether the current version is blacklisted.
    @Persisted(key: "currentVersionBlackListed") private var currentVersionBlackListed: Bool = false
    // Optional explanation from the matching blacklist entry, shown in the critical update alert.
    @Persisted(key: "currentVersionBlacklistMessage") private var currentVersionBlacklistMessage: String? = nil
    // Commit SHA of the build for which data was last fetched (blacklist entries can target a commit).
    @Persisted(key: "cachedForCommitSHA") private var cachedForCommitSHA: String? = nil
    // Timestamp for the last time a blacklist notification was shown.
    @Persisted(key: "lastBlacklistNotificationShown") private var lastBlacklistNotificationShown: Date? = .distantPast
    // Timestamp for the last time a version update notification was shown.
    @Persisted(key: "lastVersionUpdateNotificationShown") private var lastVersionUpdateNotificationShown: Date? = .distantPast
    // Timestamp for the last time an expiration notification was shown.
    @Persisted(key: "lastExpirationNotificationShown") private var lastExpirationNotificationShown: Date? = .distantPast

    // Dev version properties
    // Cached app version for which dev data was last fetched.
    @Persisted(key: "cachedForDevVersion") private var cachedForDevVersion: String? = nil
    // The latest dev version fetched from GitHub.
    @Persisted(key: "latestDevVersion") private var persistedLatestDevVersion: String? = nil
    // The date when the latest dev version was checked.
    @Persisted(key: "latestDevVersionChecked") private var latestDevVersionChecked: Date? = .distantPast

    // MARK: - Nested Types

    // GitHubDataType defines the type of data to fetch from GitHub for version checking.
    private enum GitHubDataType {
        // The configuration file containing version information.
        case versionConfig
        // The configuration file containing dev version information.
        case devVersionConfig
        // The JSON file listing blacklisted versions.
        case blacklistedVersions

        // Returns the URL string associated with the data type.
        var url: String {
            switch self {
            case .versionConfig:
                return "https://raw.githubusercontent.com/nightscout/Trio/refs/heads/main/Config.xcconfig"
            case .devVersionConfig:
                return "https://raw.githubusercontent.com/nightscout/Trio/refs/heads/dev/Config.xcconfig"
            case .blacklistedVersions:
                return "https://raw.githubusercontent.com/nightscout/Trio/refs/heads/main/blacklisted-versions.json"
            }
        }
    }

    // Model for decoding the blacklist JSON from GitHub.
    //
    // BACKWARD COMPATIBILITY: builds released before `branch` / `sha` / `message` existed decode
    // this same file with
    //
    //     struct Blacklist: Decodable { let blacklistedVersions: [VersionEntry] }
    //     struct VersionEntry: Decodable { let version: String }
    //
    // and wrap the whole decode in `try?`. JSONDecoder ignores keys a model does not declare, so adding
    // `branch`, `sha` and `message` to an entry is safe for those builds (they show only the standard
    // text). But every entry MUST keep a string `version`: a single entry without one makes the old
    // decode throw, and the old builds then treat the list as empty and stop warning about every
    // blacklisted version.
    //
    // Old builds match on `version` alone, so an entry that is narrowed by `branch` / `sha` still flags
    // every pre-existing build with that version. That errs on the side of warning too often.
    struct Blacklist: Decodable {
        // Array of blacklisted version entries.
        let blacklistedVersions: [VersionEntry]

        private enum CodingKeys: String, CodingKey {
            case blacklistedVersions
        }

        // Decodes entries one at a time so that a single malformed entry (for example one that a
        // future format adds) is skipped instead of discarding the whole list.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            var entries = try container.nestedUnkeyedContainer(forKey: .blacklistedVersions)
            var decoded: [VersionEntry] = []
            while !entries.isAtEnd {
                if let entry = try? entries.decode(VersionEntry.self) {
                    decoded.append(entry)
                } else if (try? entries.decode(SkippedEntry.self)) == nil {
                    // A failed decode does not advance the container, so step past the entry; if even
                    // that fails, stop rather than loop forever.
                    break
                }
            }
            blacklistedVersions = decoded
        }

        // Accepts any JSON value without reading it, used only to advance past an entry that failed to decode.
        private struct SkippedEntry: Decodable {
            init(from _: Decoder) throws {}
        }
    }

    // Model representing a single entry in the blacklist.
    //
    // An entry matches the running build when every field it specifies matches:
    // - `version` (required) must equal the app's `CFBundleShortVersionString`.
    // - `branch` (optional) must equal the branch recorded in BuildDetails.plist.
    // - `sha` (optional) must match the commit recorded in BuildDetails.plist. Builds record an
    //   abbreviated SHA (7+ characters), so either value may be a prefix of the other; at least
    //   7 characters must overlap, compared case-insensitively.
    //
    // `message` (optional) is not used for matching. When present it is shown in the critical update
    // alert, below the standard text, to explain the problem or what to do.
    //
    // Example:
    //     { "version": "0.6.0.12", "branch": "dev", "sha": "a1b2c3d", "message": "Fixes a bolus issue." }
    struct VersionEntry: Decodable, Equatable {
        // The version string that is blacklisted. Required so that older builds can still decode the list.
        let version: String
        // The branch the blacklisted build was made from, or `nil` to match any branch.
        let branch: String?
        // The commit SHA (full or abbreviated) of the blacklisted build, or `nil` to match any commit.
        let sha: String?
        // Optional text shown in the critical update alert for builds this entry matches.
        let message: String?

        init(version: String, branch: String? = nil, sha: String? = nil, message: String? = nil) {
            self.version = version
            self.branch = branch
            self.sha = sha
            self.message = message
        }

        // The message to show, or `nil` if the entry has none (empty or whitespace-only counts as none).
        var displayMessage: String? {
            Self.normalized(message)
        }

        // Shortest SHA prefix accepted as a match, the length `capture-build-details.sh` records.
        static let minimumSHAPrefixLength = 7

        // Returns `true` if this entry applies to a build with the given version, branch and commit.
        func matches(version currentVersion: String, branch currentBranch: String?, sha currentSHA: String?) -> Bool {
            guard version == currentVersion else {
                return false
            }

            if let branch = Self.normalized(branch) {
                guard let currentBranch = Self.normalized(currentBranch), branch == currentBranch else {
                    return false
                }
            }

            if let sha = Self.normalized(sha)?.lowercased() {
                guard let currentSHA = Self.normalized(currentSHA)?.lowercased(),
                      min(sha.count, currentSHA.count) >= Self.minimumSHAPrefixLength,
                      sha.hasPrefix(currentSHA) || currentSHA.hasPrefix(sha)
                else {
                    return false
                }
            }

            return true
        }

        // Treats empty or whitespace-only strings as absent.
        private static func normalized(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return nil
            }
            return trimmed
        }
    }

    // Returns whether any entry in the blacklist applies to the given build, and the message of the
    // first matching entry that has one.
    static func blacklistStatus(
        entries: [VersionEntry],
        version: String,
        branch: String?,
        sha: String?
    ) -> (isBlacklisted: Bool, message: String?) {
        let matching = entries.filter { $0.matches(version: version, branch: branch, sha: sha) }
        return (!matching.isEmpty, matching.lazy.compactMap(\.displayMessage).first)
    }

    // Returns `true` if any entry in the blacklist applies to the given build.
    static func isBlacklisted(
        entries: [VersionEntry],
        version: String,
        branch: String?,
        sha: String?
    ) -> Bool {
        blacklistStatus(entries: entries, version: version, branch: branch, sha: sha).isBlacklisted
    }

    // Builds the body of the critical update alert, appending the blacklist entry's message if there is one.
    static func blacklistAlertMessage(entryMessage: String?) -> String {
        let standard = String(
            localized: "The current version has a critical issue and should be updated as soon as possible.",
            comment: "Message for critical update alert"
        )
        guard let entryMessage = entryMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !entryMessage.isEmpty
        else {
            return standard
        }
        return standard + "\n\n" + entryMessage
    }

    // MARK: - Public Methods

    // Checks for a new or blacklisted version and presents an alert if necessary.
    //
    // This method determines whether there is an update or if the current version is blacklisted.
    // Depending on the result, it displays an alert on the given view controller, ensuring that alerts
    // are not shown too frequently (24 hours for blacklist and 2 weeks for update notifications).
    //
    // - Parameter viewController: The UIViewController on which to present any alerts.
    func checkAndNotifyVersionStatus(in viewController: UIViewController) {
        Task {
            let (latestVersion, isNewer, isBlacklisted, blacklistMessage) = await checkForNewVersion()
            let now = Date()

            // If the current version is blacklisted, show a critical update alert if not shown in the last 24 hours.
            if isBlacklisted {
                let lastShown = self.lastBlacklistNotificationShown ?? .distantPast
                if now.timeIntervalSince(lastShown) > 86400 { // 24 hours
                    let shown = self.showAlert(
                        on: viewController,
                        title: String(localized: "Update Required", comment: "Title for critical update alert"),
                        message: Self.blacklistAlertMessage(entryMessage: blacklistMessage)
                    )
                    if shown {
                        self.lastBlacklistNotificationShown = now
                        self.lastVersionUpdateNotificationShown = now
                    }
                }
            }
            // Otherwise, if a newer version is available, show an update alert if not shown in the last 2 weeks.
            else if isNewer {
                let lastShown = self.lastVersionUpdateNotificationShown ?? .distantPast
                if now.timeIntervalSince(lastShown) > 1_209_600 { // 2 weeks
                    let versionText = latestVersion ?? String(localized: "Unknown", comment: "Fallback text for unknown version")
                    let shown = self.showAlert(
                        on: viewController,
                        title: String(localized: "Update Available", comment: "Title for update available alert"),
                        message: String(
                            localized: "A new version (\(versionText)) is available. It is recommended to update.",
                            comment: "Message for update available alert"
                        )
                    )
                    if shown {
                        self.lastVersionUpdateNotificationShown = now
                    }
                }
            }
        }
    }

    // Refreshes the version information and returns the current state (completion handler version).
    //
    // This method triggers a version check (using cached values if valid or fetching fresh data)
    // and then returns the current app version along with the latest version info, a flag indicating
    // whether the latest version is newer, and a flag indicating if the current version is blacklisted.
    //
    // - Parameter completion: A closure that receives the following parameters:
    // - currentVersion: The current app version.
    // - latestVersion: The latest version fetched from GitHub (if available).
    // - isNewer: `true` if the fetched version is newer than the current version.
    // - isBlacklisted: `true` if the current version is blacklisted.
    func refreshVersionInfo(completion: @escaping (
        String,
        String?,
        Bool,
        Bool
    ) -> Void) {
        Task {
            let result = await refreshVersionInfo()
            completion(result.currentVersion, result.latestVersion, result.isNewer, result.isBlacklisted)
        }
    }

    // Refreshes the version information and returns the current state (async version).
    //
    // This method triggers a version check (using cached values if valid or fetching fresh data)
    // and then returns the current app version along with the latest version info, a flag indicating
    // whether the latest version is newer, and a flag indicating if the current version is blacklisted.
    //
    // - Returns: A tuple containing:
    // - currentVersion: The current app version.
    // - latestVersion: The latest version fetched from GitHub (if available).
    // - isNewer: `true` if the fetched version is newer than the current version.
    // - isBlacklisted: `true` if the current version is blacklisted.
    func refreshVersionInfo() async -> (currentVersion: String, latestVersion: String?, isNewer: Bool, isBlacklisted: Bool) {
        let currentVersion = version()
        let (latestVersion, isNewer, isBlacklisted, _) = await checkForNewVersion()
        return (currentVersion, latestVersion, isNewer, isBlacklisted)
    }

    // Checks for the latest dev version with caching and comparison (completion handler version).
    //
    // This method attempts to use cached dev version data if it is less than 24 hours old and
    // corresponds to the current app version. If the cache is invalid or outdated,
    // it fetches fresh data from GitHub.
    //
    // - Parameter completion: A closure that receives:
    // - latestDevVersion: The latest dev version string (if available).
    // - isNewer: `true` if the fetched dev version is newer than the current version.
    func checkForNewDevVersion(completion: @escaping (String?, Bool) -> Void) {
        Task {
            let result = await checkForNewDevVersion()
            completion(result.0, result.1)
        }
    }

    // Checks for the latest dev version with caching and comparison (async version).
    //
    // This method attempts to use cached dev version data if it is less than 24 hours old and
    // corresponds to the current app version. If the cache is invalid or outdated,
    // it fetches fresh data from GitHub.
    //
    // - Returns: A tuple containing:
    // - latestDevVersion: The latest dev version string (if available).
    // - isNewer: `true` if the fetched dev version is newer than the current version.
    func checkForNewDevVersion() async -> (String?, Bool) {
        // For dev version, we need to compare against the current dev version, not the main version
        let currentDevVersion = Bundle.main.object(forInfoDictionaryKey: "AppDevVersion") as? String ?? version()
        let now = Date()

        // Retrieve cached values
        let lastChecked = latestDevVersionChecked ?? .distantPast
        let cachedVersion = cachedForDevVersion
        let persistedLatestDev = persistedLatestDevVersion

        // Use cached data if it is valid (less than 24 hours old) and matches the current version
        if let cachedVersion = cachedVersion,
           cachedVersion == currentDevVersion,
           now.timeIntervalSince(lastChecked) < 24 * 3600,
           let persistedLatestDev = persistedLatestDev
        {
            let isNewer = isVersion(persistedLatestDev, newerThan: currentDevVersion)
            return (persistedLatestDev, isNewer)
        }

        // Otherwise, fetch fresh data from GitHub and update the cache
        return await fetchDevVersionAndUpdateCache(currentVersion: currentDevVersion)
    }

    // Fetches dev version data from GitHub, updates persisted values, and returns the result.
    //
    // - Parameters:
    // - currentVersion: The current app version.
    // - Returns: A tuple containing:
    // - latestDevVersion: The latest dev version string from GitHub (if available).
    // - isNewer: `true` if the fetched dev version is newer than the current version.
    private func fetchDevVersionAndUpdateCache(currentVersion: String) async -> (String?, Bool) {
        let versionData = await fetchData(for: .devVersionConfig)

        // Parse the dev version from the fetched configuration data
        let configContents = versionData.flatMap { String(data: $0, encoding: .utf8) }
        let fetchedDevVersion = configContents.flatMap { self.parseDevVersionFromConfig(contents: $0) }

        #if DEBUG
            print("AppVersionChecker.fetchDevVersion: Current dev version: \(currentVersion)")
            print("AppVersionChecker.fetchDevVersion: Fetched dev version: \(fetchedDevVersion ?? "nil")")
            if let contents = configContents {
                let lines = contents.split(separator: "\n")
                for line in lines where line.contains("VERSION") {
                    print("AppVersionChecker.fetchDevVersion: Config line: \(line)")
                }
            }
        #endif

        // Determine if the fetched dev version is newer than the current version
        let isNewer = fetchedDevVersion.map {
            self.isVersion($0, newerThan: currentVersion)
        } ?? false

        // Update persisted cache
        persistedLatestDevVersion = fetchedDevVersion
        latestDevVersionChecked = Date()
        cachedForDevVersion = currentVersion

        return (fetchedDevVersion, isNewer)
    }

    // MARK: - Core Version Checking Logic

    // Checks whether there is a new or blacklisted version (completion handler version).
    //
    // This method attempts to use cached version data if it is less than 24 hours old and
    // corresponds to the current app version. If the cache is invalid or outdated,
    // it fetches fresh data from GitHub.
    //
    // - Parameter completion: A closure that receives:
    // - latestVersion: The latest version string (if available).
    // - isNewer: `true` if the fetched version is newer than the current version.
    // - isBlacklisted: `true` if the current version is blacklisted.
    private func checkForNewVersion(completion: @escaping (String?, Bool, Bool) -> Void) {
        Task {
            let result = await checkForNewVersion()
            completion(result.0, result.1, result.2)
        }
    }

    // Checks whether there is a new or blacklisted version (async version).
    //
    // This method attempts to use cached version data if it is less than 24 hours old and
    // corresponds to the current app version. If the cache is invalid or outdated,
    // it fetches fresh data from GitHub.
    //
    // - Returns: A tuple containing:
    // - latestVersion: The latest version string (if available).
    // - isNewer: `true` if the fetched version is newer than the current version.
    // - isBlacklisted: `true` if the current version is blacklisted.
    // - blacklistMessage: The matching blacklist entry's message, if any.
    private func checkForNewVersion() async -> (String?, Bool, Bool, String?) {
        let currentVersion = version()
        let now = Date()

        // Retrieve cached values.
        let lastChecked = latestVersionChecked ?? .distantPast
        let cachedVersion = cachedForVersion
        let persistedLatest = persistedLatestVersion
        let isBlacklistedCached = currentVersionBlackListed
        let blacklistMessageCached = currentVersionBlacklistMessage

        // If the current app version has changed, reset notification timestamps.
        if let cachedVersion = cachedVersion, cachedVersion != currentVersion {
            lastBlacklistNotificationShown = .distantPast
            lastVersionUpdateNotificationShown = .distantPast
        }

        // Use cached data if it is valid (less than 24 hours old) and matches the current version and
        // commit. The commit is checked too because blacklist entries can target a single commit, and
        // a rebuild from another commit keeps the same version string.
        if let cachedVersion = cachedVersion,
           cachedVersion == currentVersion,
           cachedForCommitSHA == currentCommitSHA(),
           now.timeIntervalSince(lastChecked) < 24 * 3600,
           let persistedLatest = persistedLatest
        {
            let isNewer = isVersion(persistedLatest, newerThan: currentVersion)
            return (persistedLatest, isNewer, isBlacklistedCached, isBlacklistedCached ? blacklistMessageCached : nil)
        }

        // Otherwise, fetch fresh data from GitHub and update the cache.
        return await fetchDataAndUpdateCache(currentVersion: currentVersion)
    }

    // Fetches version and blacklist data from GitHub, updates persisted values, and returns the result.
    //
    // This method performs two parallel network requests: one for the version configuration and one for the
    // blacklisted versions. After parsing the fetched data and comparing version values, it updates the cache and
    // returns the results.
    //
    // - Parameters:
    // - currentVersion: The current app version.
    // - Returns: A tuple containing:
    // - latestVersion: The latest version string from GitHub (if available).
    // - isNewer: `true` if the fetched version is newer than the current version.
    // - isBlacklisted: `true` if the current version is blacklisted.
    // - blacklistMessage: The matching blacklist entry's message, if any.
    private func fetchDataAndUpdateCache(currentVersion: String) async -> (String?, Bool, Bool, String?) {
        // Fetch both data types in parallel
        async let versionData = fetchData(for: .versionConfig)
        async let blacklistData = fetchData(for: .blacklistedVersions)

        let (versionDataResult, blacklistDataResult) = await (versionData, blacklistData)

        // Parse the version from the fetched configuration data.
        let fetchedVersion = versionDataResult
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap { self.parseVersionFromConfig(contents: $0) }

        // Determine if the fetched version is newer than the current version.
        let isNewer = fetchedVersion.map {
            self.isVersion($0, newerThan: currentVersion)
        } ?? false

        // Determine if the current build is blacklisted, by version and, where an entry specifies them,
        // by branch and commit SHA.
        let entries = (try? blacklistDataResult.flatMap {
            try JSONDecoder().decode(Blacklist.self, from: $0)
        })?.blacklistedVersions ?? []
        let (isBlacklisted, blacklistMessage) = Self.blacklistStatus(
            entries: entries,
            version: currentVersion,
            branch: currentBranch(),
            sha: currentCommitSHA()
        )

        // Update persisted cache.
        persistedLatestVersion = fetchedVersion
        latestVersionChecked = Date()
        currentVersionBlackListed = isBlacklisted
        currentVersionBlacklistMessage = blacklistMessage
        cachedForVersion = currentVersion
        cachedForCommitSHA = currentCommitSHA()

        return (fetchedVersion, isNewer, isBlacklisted, blacklistMessage)
    }

    // MARK: - Data Fetching Helper

    // Fetches data from GitHub for a specified data type.
    //
    // This helper method builds a URL from the provided GitHubDataType and executes a network request.
    // If the request is successful and returns valid data (HTTP status 200), the data is returned.
    //
    // - Parameters:
    // - dataType: The type of GitHub data to fetch (version configuration or blacklisted versions).
    // - Returns: The fetched data as an optional `Data` object.
    private func fetchData(for dataType: GitHubDataType) async -> Data? {
        guard let url = URL(string: dataType.url) else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    // Legacy completion handler version for existing code
    private func fetchData(for dataType: GitHubDataType, completion: @escaping (Data?) -> Void) {
        guard let url = URL(string: dataType.url) else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                completion(nil)
                return
            }
            completion(data)
        }.resume()
    }

    // MARK: - Helpers

    // Parses the version string from the contents of a configuration file.
    //
    // The method scans each line of the provided content for an occurrence of "APP_VERSION" and then
    // extracts the version number following the "=" delimiter.
    //
    // - Parameter contents: A string containing the contents of the configuration file.
    // - Returns: The extracted version string if found; otherwise, `nil`.
    private func parseVersionFromConfig(contents: String) -> String? {
        let lines = contents.split(separator: "\n")
        for line in lines {
            if line.contains("APP_VERSION"), !line.contains("DEV") {
                let components = line.split(separator: "=").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if components.count > 1 {
                    return components[1]
                }
            }
        }
        return nil
    }

    // Parses the dev version string from the contents of a configuration file.
    //
    // The method scans each line of the provided content for an occurrence of "APP_DEV_VERSION" and then
    // extracts the version number following the "=" delimiter.
    //
    // - Parameter contents: A string containing the contents of the configuration file.
    // - Returns: The extracted dev version string if found; otherwise, `nil`.
    private func parseDevVersionFromConfig(contents: String) -> String? {
        let lines = contents.split(separator: "\n")
        for line in lines {
            if line.contains("APP_DEV_VERSION") {
                let components = line.split(separator: "=").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if components.count > 1 {
                    return components[1]
                }
            }
        }
        return nil
    }

    // Compares two version strings to determine if the fetched version is newer than the current version.
    //
    // The version strings are split into numeric components and compared sequentially.
    // If any component of the fetched version is greater than its counterpart in the current version,
    // the function returns `true`; if lower, it returns `false`.
    //
    // - Parameters:
    // - fetchedVersion: The version string obtained from GitHub.
    // - currentVersion: The current app version.
    // - Returns: `true` if the fetched version is newer than the current version; otherwise, `false`.
    private func isVersion(_ fetchedVersion: String, newerThan currentVersion: String) -> Bool {
        let fetchedComponents = fetchedVersion.split(separator: ".").map { Int($0) ?? 0 }
        let currentComponents = currentVersion.split(separator: ".").map { Int($0) ?? 0 }

        let maxCount = max(fetchedComponents.count, currentComponents.count)
        for i in 0 ..< maxCount {
            let fetched = i < fetchedComponents.count ? fetchedComponents[i] : 0
            let current = i < currentComponents.count ? currentComponents[i] : 0
            if fetched > current {
                return true
            } else if fetched < current {
                return false
            }
        }
        return false
    }

    // Retrieves the current app version from the main bundle.
    //
    // - Returns: The current app version as defined in the app's Info.plist under "CFBundleShortVersionString",
    // or `"Unknown"` if not available.
    private func version() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    // Retrieves the branch the app was built from, as recorded in BuildDetails.plist.
    //
    // - Returns: The branch (or tag) name, or `nil` if it was not recorded.
    private func currentBranch() -> String? {
        BuildDetails.shared.dict["com-trio-branch"] as? String
    }

    // Retrieves the commit SHA the app was built from, as recorded in BuildDetails.plist.
    //
    // - Returns: The abbreviated commit SHA, or `nil` if it was not recorded.
    private func currentCommitSHA() -> String? {
        BuildDetails.shared.dict["com-trio-commit-sha"] as? String
    }

    // Presents an alert on the specified view controller with a given title and message.
    //
    // The alert is dispatched to the main thread to ensure UI updates occur correctly.
    //
    // Presentation is skipped when the view controller is already showing something - for example
    // the non-release build warning from DevelopmentBranchAlerter, which runs just before this.
    // UIKit drops a second presentation silently, so the caller is told whether the alert actually
    // appeared and can leave its throttle untouched to retry on the next foreground.
    //
    // - Parameters:
    // - viewController: The UIViewController on which the alert should be presented.
    // - title: The title text for the alert.
    // - message: The body message of the alert.
    // - Returns: `true` if the alert was presented; `false` if another alert was already showing.
    private func showAlert(on viewController: UIViewController, title: String, message: String) -> Bool {
        guard viewController.presentedViewController == nil else {
            return false
        }

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        viewController.present(alert, animated: true)
        return true
    }
}
