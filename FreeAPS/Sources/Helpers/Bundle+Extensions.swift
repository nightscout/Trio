import Foundation

extension Bundle {
    var releaseVersionNumber: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var buildVersionNumber: String? {
        infoDictionary?["CFBundleVersion"] as? String
    }

    var buildDate: Date {
        if let infoPath = Bundle.main.path(forResource: "Info", ofType: "plist"),
           let infoAttr = try? FileManager.default.attributesOfItem(atPath: infoPath),
           let infoDate = infoAttr[.modificationDate] as? Date
        {
            return infoDate
        }
        return Date()
    }

    var profileExpiration: String {
        guard
            let profilePath = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
            let profileData = try? Data(contentsOf: URL(fileURLWithPath: profilePath)),
            // Note: We use `NSString` instead of `String`, because it makes it easier working with regex, ranges, substring etc.
            let profileNSString = NSString(data: profileData, encoding: String.Encoding.ascii.rawValue)
        else {
            print(
                "WARNING: Could not find or read `embedded.mobileprovision`. If running on Simulator, there are no provisioning profiles."
            )
            return "N/A"
        }

        // NOTE: We have the `[\\W]*?` check to make sure that variations in number of tabs or new lines in the future does not influence the result.
        guard let regex = try? NSRegularExpression(pattern: "<key>ExpirationDate</key>[\\W]*?<date>(.*?)</date>", options: [])
        else {
            print("Warning: Could not create regex.")
            return "N/A"
        }

        let regExMatches = regex.matches(
            in: profileNSString as String,
            options: [],
            range: NSRange(location: 0, length: profileNSString.length)
        )

        // NOTE: range `0` corresponds to the full regex match, so to get the first capture group, we use range `1`
        guard let rangeOfCapturedGroupForDate = regExMatches.first?.range(at: 1) else {
            print("Warning: Could not find regex match or capture group.")
            return "N/A"
        }

        let dateWithTimeAsString = profileNSString.substring(with: rangeOfCapturedGroupForDate)

        guard let dateAsStringIndex = dateWithTimeAsString.firstIndex(of: "T") else {
            return ""
        }
        return String(dateWithTimeAsString[..<dateAsStringIndex])
    }
}
