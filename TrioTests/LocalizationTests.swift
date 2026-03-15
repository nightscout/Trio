
import Foundation
import Testing

private let bundle = Bundle.main

@Suite("Localization Tests", .serialized) struct LocalizationTests {
    @Test("No stray % inside format strings") func testNoStrayPercent() {
        // Array to collect strings with issues
        var offenders: [(lang: String, key: String, value: String, file: String)] = []

        // Regular expression patterns
        let placeholderPattern = "%[0-9]*\\$?[.,]?[0-9]*[a-zA-Z@]" // Matches placeholders like %@, %d, %1$@
        let escapedPercentPattern = "%%" // Matches escaped percent signs
        let percentPattern = "%" // Matches any percent sign

        // Compile regexes (force-unwrapped since patterns are static and valid)
        let placeholderRegex = try! NSRegularExpression(pattern: placeholderPattern)
        let escapedPercentRegex = try! NSRegularExpression(pattern: escapedPercentPattern)
        let percentRegex = try! NSRegularExpression(pattern: percentPattern)

        // Assume 'bundle' is accessible, e.g., Bundle.main
        for locale in bundle.localizations where locale != "Base" {
            guard let lproj = bundle.path(forResource: locale, ofType: "lproj"),
                  let files = FileManager.default.enumerator(atPath: lproj) else { continue }

            // Iterate over .strings files in the localization directory
            for case let f as String in files where f.hasSuffix(".strings") {
                let path = (lproj as NSString).appendingPathComponent(f)
                guard let table = NSDictionary(contentsOfFile: path) as? [String: String] else { continue }

                // Check each key-value pair in the .strings file
                for (key, value) in table {
                    let nsValue = value as NSString
                    let range = NSRange(location: 0, length: nsValue.length)

                    // Determine if the value contains any placeholders
                    let hasPlaceholders = placeholderRegex.firstMatch(in: value, range: range) != nil

                    // Only check for stray % if the value has placeholders
                    if hasPlaceholders {
                        // Find all ranges covered by placeholders and escaped %%
                        let placeholderMatches = placeholderRegex.matches(in: value, range: range)
                        let escapedMatches = escapedPercentRegex.matches(in: value, range: range)
                        let coveredRanges = (placeholderMatches + escapedMatches).map(\.range)

                        // Find all % signs in the value
                        let percentMatches = percentRegex.matches(in: value, range: range)

                        // Check each % to see if it's stray (not covered by a placeholder or %%)
                        for percentMatch in percentMatches {
                            let percentLocation = percentMatch.range.location
                            let isCovered = coveredRanges.contains { NSLocationInRange(percentLocation, $0) }
                            if !isCovered {
                                offenders.append((lang: locale, key: key, value: value, file: f))
                                break // Stop checking this string after finding an issue
                            }
                        }
                    }
                    // If no placeholders, skip the check (single % is allowed)
                }
            }
        }

        // Assert that no offenders were found using Testing's #expect
        #expect(
            offenders.isEmpty,
            """
            Found \(offenders.count) string(s) that still have a single % although \
            the value contains printf placeholders:

            \(offenders.map { "\($0.lang) – \($0.file)\n⟨key⟩   \($0.key)\n⟨value⟩ \($0.value)" }
                .joined(separator: "\n\n"))
            """
        )
    }
}
