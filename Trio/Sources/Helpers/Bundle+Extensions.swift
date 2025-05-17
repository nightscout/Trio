import Foundation

extension Bundle {
    var releaseVersionNumber: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var buildVersionNumber: String? {
        infoDictionary?["CFBundleVersion"] as? String
    }

    var profileExpirationDateString: String? {
        guard
            let profilePath = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
            let profileData = try? Data(contentsOf: URL(fileURLWithPath: profilePath)),
            // Note: We use `NSString` instead of `String`, because it makes it easier working with regex, ranges, substring etc.
            let profileNSString = NSString(data: profileData, encoding: String.Encoding.ascii.rawValue)
        else {
            print(
                "WARNING: Could not find or read `embedded.mobileprovision`. If running on Simulator, there are no provisioning profiles."
            )
            return nil
        }

        let regexPattern = "<key>ExpirationDate</key>[\\W]*?<date>(.*?)</date>"
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: []),
              let match = regex.firstMatch(
                  in: profileNSString as String,
                  options: [],
                  range: NSRange(location: 0, length: profileNSString.length)
              ),
              let range = Range(match.range(at: 1), in: profileNSString as String)
        else {
            print("Warning: Could not create regex or find match.")
            return nil
        }

        return String(profileNSString.substring(with: NSRange(range, in: profileNSString as String)))
    }

    var profileExpirationDate: Date? {
        guard let dateString = profileExpirationDateString else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dateFormatter.date(from: dateString)
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
