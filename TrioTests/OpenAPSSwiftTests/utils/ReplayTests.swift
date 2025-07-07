import Foundation

/// Flag to enable replay tests.
///
/// These test are only used for debugging so normally they should be disabled. But
/// if you're debugging the oref-swift functions they are extremely useful. To enable them
/// add these lines to your ConfigOverride.xcconfig file:
/// ```
/// ENABLE_REPLAY_TESTS = YES
/// ```
enum ReplayTests {
    static var enabled: Bool {
        let bundle = Bundle(for: BundleReference.self)
        return bundle.object(forInfoDictionaryKey: "EnableReplayTests") as? String == "YES"
    }

    /// Timezone to use for replay tests.
    ///
    /// This is used to filter replay test files by timezone. If not set, it defaults to "America/Los_Angeles".
    /// To set it, add this line to your ConfigOverride.xcconfig file:
    /// ```
    /// REPLAY_TEST_TIMEZONE = Europe/Berlin
    /// ```
    static var timezone: String {
        let bundle = Bundle(for: BundleReference.self)
        return bundle.object(forInfoDictionaryKey: "ReplayTestTimezone") as? String ?? "America/Los_Angeles"
    }
}
