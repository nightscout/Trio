import Foundation
import Swinject

class BuildDetails: Injectable {
    static var shared = BuildDetails()
    @Injected() internal var nightscoutManager: NightscoutManager!

    let dict: [String: Any]
    let previousExpireDateKey = "previousExpireDate"

    init() {
        guard let url = Bundle.main.url(forResource: "BuildDetails", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let parsed = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            dict = [:]
            return
        }
        dict = parsed
    }

    var buildDateString: String? {
        dict["com-trio-build-date"] as? String
    }

    var trioBranch: String {
        dict["com-trio-branch"] as? String ?? String(localized: "Unknown")
    }

    var trioCommitSHA: String {
        dict["com-trio-commit-sha"] as? String ?? String(localized: "Unknown")
    }

    var branchAndSha: String {
        "\(trioBranch) \(trioCommitSHA)"
    }

    /// Returns a dictionary of submodule details.
    /// The keys are the submodule names, and the values are tuples (branch, commitSHA).
    var submodules: [String: (branch: String, commitSHA: String)] {
        guard let subs = dict["com-trio-submodules"] as? [String: [String: Any]] else {
            return [:]
        }
        var result = [String: (branch: String, commitSHA: String)]()
        for (name, info) in subs {
            let branch = info["branch"] as? String ?? String(localized: "Unknown")
            let commitSHA = info["commit_sha"] as? String ?? String(localized: "Unknown")
            result[name] = (branch: branch, commitSHA: commitSHA)
        }
        return result
    }

    // Determine if the build is from TestFlight
    func isTestFlightBuild() -> Bool {
        #if targetEnvironment(simulator)
            return false
        #else
            if Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil {
                return false
            }
            guard let receiptName = Bundle.main.appStoreReceiptURL?.lastPathComponent else {
                return false
            }
            return "sandboxReceipt".caseInsensitiveCompare(receiptName) == .orderedSame
        #endif
    }

    // Parse the build date string into a Date object
    func buildDate() -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE MMM d HH:mm:ss 'UTC' yyyy"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        guard let dateString = buildDateString,
              let date = dateFormatter.date(from: dateString)
        else {
            return nil
        }
        return date
    }

    // Calculate the expiration date based on the build type
    func calculateExpirationDate() -> Date? {
        if isTestFlightBuild(), let buildDate = buildDate() {
            // For TestFlight, add 90 days to the build date
            return Calendar.current.date(byAdding: .day, value: 90, to: buildDate)!
        } else {
            return Bundle.main.profileExpirationDate
        }
    }

    // Expiration header based on build type
    var expirationHeaderString: String {
        if isTestFlightBuild() {
            return String(localized: "Beta (TestFlight) Expires")
        } else {
            return String(localized: "App Expires")
        }
    }

    // Upload new profile if expire date has changed
    func handleExpireDateChange() async throws
    {
        if nightscoutManager == nil {
            await injectServices(TrioApp.resolver)
        }

        let previousExpireDate = UserDefaults.standard.object(forKey: previousExpireDateKey) as? Date
        let expireDate = calculateExpirationDate()

        if previousExpireDate != expireDate {
            debug(.nightscout, "New build expire date detected, uploading profile")
            try await nightscoutManager.uploadProfiles()
        }
    }

    // Store the uploaded expire date
    func recordUploadedExpireDate(expireDate: Date?) {
        if let expireDate = expireDate {
            UserDefaults.standard.set(expireDate, forKey: previousExpireDateKey)
        } else {
            UserDefaults.standard.removeObject(forKey: previousExpireDateKey)
        }
    }
}
