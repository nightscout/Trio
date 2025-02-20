import UIKit

final class AppVersionChecker {
    static let shared = AppVersionChecker()
    private init() {}

    // MARK: - Persisted Properties

    @Persisted(key: "cachedForVersion") private var cachedForVersion: String? = nil
    @Persisted(key: "latestVersion") private var persistedLatestVersion: String? = nil
    @Persisted(key: "latestVersionChecked") private var latestVersionChecked: Date? = .distantPast
    @Persisted(key: "currentVersionBlackListed") private var currentVersionBlackListed: Bool = false
    @Persisted(key: "lastBlacklistNotificationShown") private var lastBlacklistNotificationShown: Date? = .distantPast
    @Persisted(key: "lastVersionUpdateNotificationShown") private var lastVersionUpdateNotificationShown: Date? = .distantPast
    @Persisted(key: "lastExpirationNotificationShown") private var lastExpirationNotificationShown: Date? = .distantPast

    // MARK: - Nested Types

    /// Types of data we fetch from GitHub for version checking.
    private enum GitHubDataType {
        case versionConfig
        case blacklistedVersions

        var url: String {
            switch self {
            case .versionConfig:
                return "https://raw.githubusercontent.com/nightscout/Trio/refs/heads/main/Config.xcconfig"
            case .blacklistedVersions:
                return "https://raw.githubusercontent.com/nightscout/Trio/refs/heads/main/blacklisted-versions.json"
            }
        }
    }

    /// Structures for decoding GitHub JSON data.
    private struct Blacklist: Decodable {
        let blacklistedVersions: [VersionEntry]
    }

    private struct VersionEntry: Decodable {
        let version: String
    }

    // MARK: - Public Methods

    /// Checks for new or blacklisted versions and presents an alert if needed.
    func checkAndNotifyVersionStatus(in viewController: UIViewController) {
        checkForNewVersion { [weak viewController] latestVersion, isNewer, isBlacklisted in
            guard let vc = viewController else { return }
            let now = Date()

            // Check for critical (blacklisted) version.
            if isBlacklisted {
                let lastShown = self.lastBlacklistNotificationShown ?? .distantPast
                if now.timeIntervalSince(lastShown) > 86400 { // 24 hours
                    self.showAlert(
                        on: vc,
                        title: "Update Required",
                        message: "The current version has a critical issue and should be updated as soon as possible."
                    )
                    self.lastBlacklistNotificationShown = now
                    self.lastVersionUpdateNotificationShown = now
                }
            }
            // Check for a new version available.
            else if isNewer {
                let lastShown = self.lastVersionUpdateNotificationShown ?? .distantPast
                if now.timeIntervalSince(lastShown) > 1_209_600 { // 2 weeks
                    let versionText = latestVersion ?? "Unknown"
                    self.showAlert(
                        on: vc,
                        title: "Update Available",
                        message: "A new version (\(versionText)) is available. It is recommended to update."
                    )
                    self.lastVersionUpdateNotificationShown = now
                }
            }
        }
    }

    func refreshVersionInfo(completion: @escaping (
        String /* currentVersion */,
        String? /* latestVersion */,
        Bool /* isNewer */,
        Bool /* isBlacklisted */
    ) -> Void) {
        let currentVersion = version()
        checkForNewVersion { latestVersion, isNewer, isBlacklisted in
            completion(currentVersion, latestVersion, isNewer, isBlacklisted)
        }
    }

    // MARK: - Core Version Checking Logic

    /// Checks if there is a new or blacklisted version.
    private func checkForNewVersion(completion: @escaping (String?, Bool, Bool) -> Void) {
        let currentVersion = version()
        let now = Date()

        // Retrieve cached values.
        let lastChecked = latestVersionChecked ?? .distantPast
        let cachedVersion = cachedForVersion
        let persistedLatest = persistedLatestVersion
        let isBlacklistedCached = currentVersionBlackListed

        // Reset notifications if the current app version differs from the cached one.
        if let cachedVersion = cachedVersion, cachedVersion != currentVersion {
            lastBlacklistNotificationShown = .distantPast
            lastVersionUpdateNotificationShown = .distantPast
        }

        // If cache is valid (<24 hours old) and for the current version, use it.
        if let cachedVersion = cachedVersion,
           cachedVersion == currentVersion,
           now.timeIntervalSince(lastChecked) < 24 * 3600,
           let persistedLatest = persistedLatest
        {
            let isNewer = isVersion(persistedLatest, newerThan: currentVersion)
            completion(persistedLatest, isNewer, isBlacklistedCached)
            return
        }

        // Otherwise, fetch fresh data and update the cache.
        fetchDataAndUpdateCache(currentVersion: currentVersion, completion: completion)
    }

    /// Fetches version and blacklist data from GitHub, updates persisted values, and then calls completion.
    private func fetchDataAndUpdateCache(currentVersion: String, completion: @escaping (String?, Bool, Bool) -> Void) {
        fetchData(for: .versionConfig) { versionData in
            self.fetchData(for: .blacklistedVersions) { blacklistData in
                DispatchQueue.main.async {
                    // Parse the version from the fetched config.
                    let fetchedVersion = versionData
                        .flatMap { String(data: $0, encoding: .utf8) }
                        .flatMap { self.parseVersionFromConfig(contents: $0) }

                    // Compare versions.
                    let isNewer = fetchedVersion.map {
                        self.isVersion($0, newerThan: currentVersion)
                    } ?? false

                    // Parse and determine if current version is blacklisted.
                    let isBlacklisted = (try? blacklistData.flatMap {
                        try JSONDecoder().decode(Blacklist.self, from: $0)
                    })?.blacklistedVersions
                        .map(\.version)
                        .contains(currentVersion) ?? false

                    // Update persisted cache.
                    self.persistedLatestVersion = fetchedVersion
                    self.latestVersionChecked = Date()
                    self.currentVersionBlackListed = isBlacklisted
                    self.cachedForVersion = currentVersion

                    completion(fetchedVersion, isNewer, isBlacklisted)
                }
            }
        }
    }

    // MARK: - Data Fetching Helper

    /// Fetches data from GitHub for a given data type.
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

    /// Parses the version string from a configuration file's content.
    private func parseVersionFromConfig(contents: String) -> String? {
        let lines = contents.split(separator: "\n")
        for line in lines {
            if line.contains("APP_VERSION") {
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

    /// Compares two version strings to determine if the fetched version is newer.
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

    /// Returns the current app version.
    private func version() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    /// Presents an alert on the provided view controller.
    private func showAlert(on viewController: UIViewController, title: String, message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            viewController.present(alert, animated: true)
        }
    }
}
