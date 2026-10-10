@testable import OrefAlgorithmExample
import Testing

/// Drives the example consumer in-process. Every other test in this package reaches the
/// algorithm through the `Trio` module alias with testable access, so this is the one test
/// that fails if a plain `import OrefAlgorithm` stops working for other projects.
@Suite("OrefAlgorithm example consumer") struct OrefAlgorithmExampleTests {
    @Test("the example reaches the public API through a plain import") func ultraRapidPeak() {
        #expect(ExampleConsumer.ultraRapidPeakMinutes() == 55)
    }
}
