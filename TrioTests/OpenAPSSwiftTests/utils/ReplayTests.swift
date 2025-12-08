import Foundation

enum ReplayTests {
    /// Flag to enable replay tests.
    ///
    /// These test are only used for debugging so normally they should be disabled. But
    /// if you're debugging the oref-swift functions they are extremely useful. To enable them
    /// add these lines to your ConfigOverride.xcconfig file:
    /// ```
    /// ENABLE_REPLAY_TESTS = YES
    /// ```
    static var enabled: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["ENABLE_REPLAY_TESTS"] == "YES" {
            return true
        }

        let bundle = Bundle(for: BundleReference.self)
        return bundle.object(forInfoDictionaryKey: "EnableReplayTests") as? String == "YES"
    }

    /// The offset for pagination of replay input files
    ///
    /// Set this offset using an environment variable or the ConfigOverride.xcconfig file.
    /// For this change to take effect you must also set the length
    /// ```
    /// HTTP_FILES_OFFSET = 2000
    /// ```
    static var filesOffset: Int? {
        let env = ProcessInfo.processInfo.environment
        if let offset = env["HTTP_FILES_OFFSET"].flatMap({ Int($0) }) {
            return offset
        }

        let bundle = Bundle(for: BundleReference.self)
        let offsetString = bundle.object(forInfoDictionaryKey: "HttpFilesOffset") as? String
        return offsetString.flatMap { Int($0) }
    }

    /// Length for pagination of replay input files
    ///
    /// Set this length using an environment variable or the ConfigOverride.xcconfig file.
    /// ```
    /// HTTP_FILES_LENGTH = 3500
    /// ```
    static var filesLength: Int? {
        let env = ProcessInfo.processInfo.environment
        if let length = env["HTTP_FILES_LENGTH"].flatMap({ Int($0) }) {
            return length
        }

        let bundle = Bundle(for: BundleReference.self)
        let lengthString = bundle.object(forInfoDictionaryKey: "HttpFilesLength") as? String
        return lengthString.flatMap { Int($0) }
    }

    /// Timezone to use for replay tests.
    ///
    /// This is used to filter replay test files by timezone. If not set, it defaults to "America/Los_Angeles".
    /// To set it, add this line to your ConfigOverride.xcconfig file:
    /// ```
    /// REPLAY_TEST_TIMEZONE = Europe/Berlin
    /// ```
    static var timezone: String {
        let env = ProcessInfo.processInfo.environment
        if let timezone = env["REPLAY_TEST_TIMEZONE"], !timezone.isEmpty {
            return timezone
        }

        let bundle = Bundle(for: BundleReference.self)
        return bundle.object(forInfoDictionaryKey: "ReplayTestTimezone") as? String ?? "America/Los_Angeles"
    }
}
