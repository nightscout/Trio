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
}
