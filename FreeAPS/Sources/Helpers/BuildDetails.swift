//
//  BuildDetails.swift
//  Trio
//
//  Created by Jonas Björkert on 2024-05-09.
//
import Foundation

class BuildDetails {
    static var `default` = BuildDetails()

    let dict: [String: Any]

    init() {
        guard let url = Bundle.main.url(forResource: "BuildDetails", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            dict = [:]
            return
        }
        dict = parsed
    }

    var buildDateString: String? {
        dict["com-trio-build-date"] as? String
    }

    var branchAndSha: String {
        let branch = dict["com-trio-branch"] as? String ?? "Unknown"
        let sha = dict["com-trio-commit-sha"] as? String ?? "Unknown"
        return "\(branch) \(sha)"
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
            return "Beta (TestFlight) Expires"
        } else {
            return "App Expires"
        }
    }
}
