import UIKit

// AppVersionChecker is a singleton responsible for checking the app's version status.
// It fetches version data from remote sources (GitHub), caches the results, and notifies the user
// if an update is available or if the current version is blacklisted.
final class AppVersionChecker {
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
    private struct Blacklist: Decodable {
        // Array of blacklisted version entries.
        let blacklistedVersions: [VersionEntry]
    }

    // Model representing a single version entry in the blacklist.
    private struct VersionEntry: Decodable {
        // The version string that is blacklisted.
        let version: String
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
        Task { @MainActor in
            let (latestVersion, isNewer, isBlacklisted) = await checkForNewVersion()
            let now = Date()

            // If the current version is blacklisted, show a critical update alert if not shown in the last 24 hours.
            if isBlacklisted {
                let lastShown = self.lastBlacklistNotificationShown ?? .distantPast
                if now.timeIntervalSince(lastShown) > 86400 { // 24 hours
                    self.showAlert(
                        on: viewController,
                        title: String(localized: "Update Required", comment: "Title for critical update alert"),
                        message: String(
                            localized: "The current version has a critical issue and should be updated as soon as possible.",
                            comment: "Message for critical update alert"
                        )
                    )
                    self.lastBlacklistNotificationShown = now
                    self.lastVersionUpdateNotificationShown = now
                }
            }
            // Otherwise, if a newer version is available, show an update alert if not shown in the last 2 weeks.
            else if isNewer {
                let lastShown = self.lastVersionUpdateNotificationShown ?? .distantPast
                if now.timeIntervalSince(lastShown) > 1_209_600 { // 2 weeks
                    let versionText = latestVersion ?? String(localized: "Unknown", comment: "Fallback text for unknown version")
                    self.showAlert(
                        on: viewController,
                        title: String(localized: "Update Available", comment: "Title for update available alert"),
                        message: String(
                            localized: "A new version (\(versionText)) is available. It is recommended to update.",
                            comment: "Message for update available alert"
                        )
                    )
                    self.lastVersionUpdateNotificationShown = now
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
        let (latestVersion, isNewer, isBlacklisted) = await checkForNewVersion()
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
    private func checkForNewVersion() async -> (String?, Bool, Bool) {
        let currentVersion = version()
        let now = Date()

        // Retrieve cached values.
        let lastChecked = latestVersionChecked ?? .distantPast
        let cachedVersion = cachedForVersion
        let persistedLatest = persistedLatestVersion
        let isBlacklistedCached = currentVersionBlackListed

        // If the current app version has changed, reset notification timestamps.
        if let cachedVersion = cachedVersion, cachedVersion != currentVersion {
            lastBlacklistNotificationShown = .distantPast
            lastVersionUpdateNotificationShown = .distantPast
        }

        // Use cached data if it is valid (less than 24 hours old) and matches the current version.
        if let cachedVersion = cachedVersion,
           cachedVersion == currentVersion,
           now.timeIntervalSince(lastChecked) < 24 * 3600,
           let persistedLatest = persistedLatest
        {
            let isNewer = isVersion(persistedLatest, newerThan: currentVersion)
            return (persistedLatest, isNewer, isBlacklistedCached)
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
    private func fetchDataAndUpdateCache(currentVersion: String) async -> (String?, Bool, Bool) {
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

        // Determine if the current version is blacklisted.
        let isBlacklisted = (try? blacklistDataResult.flatMap {
            try JSONDecoder().decode(Blacklist.self, from: $0)
        })?.blacklistedVersions
            .map(\.version)
            .contains(currentVersion) ?? false

        // Update persisted cache.
        persistedLatestVersion = fetchedVersion
        latestVersionChecked = Date()
        currentVersionBlackListed = isBlacklisted
        cachedForVersion = currentVersion

        return (fetchedVersion, isNewer, isBlacklisted)
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

    // Presents an alert on the specified view controller with a given title and message.
    //
    // The alert is dispatched to the main thread to ensure UI updates occur correctly.
    //
    // - Parameters:
    // - viewController: The UIViewController on which the alert should be presented.
    // - title: The title text for the alert.
    // - message: The body message of the alert.
    private func showAlert(on viewController: UIViewController, title: String, message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            viewController.present(alert, animated: true)
        }
    }
}
