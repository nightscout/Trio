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
}
