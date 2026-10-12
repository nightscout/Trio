@testable import OrefAlgorithmExample
import Testing

/// Drives the example consumer in-process. Every other test in this package reaches the
/// algorithm through the `Trio` module alias with testable access, so this is the one test
/// that fails if a plain `import OrefAlgorithm` stops working for other projects.
@Suite("OrefAlgorithm example consumer") struct OrefAlgorithmExampleTests {
    @Test("the example reaches the public API through a plain import") func ultraRapidPeak() {
        #expect(ExampleConsumer.ultraRapidPeakMinutes() == 55)
    }

    @Test("duplicate suspends collapse through the public dedupe") func dedupe() {
        #expect(ExampleConsumer.dedupedEventCount() == 3)
    }

    @Test("the Double boundary round-trips 0.07 exactly") func decimalBoundary() {
        #expect(ExampleConsumer.roundTrippedRate(0.07) == 0.07)
        #expect(ExampleConsumer.roundTrippedRate(1.25) == 1.25)
    }
}
