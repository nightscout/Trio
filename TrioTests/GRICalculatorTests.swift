import Foundation
import Testing

@testable import Trio

@Suite("Glycemia Risk Index") struct GRICalculatorTests {
    @Test("Empty and invalid readings are unavailable") func missingData() {
        #expect(GRICalculator.calculate(glucoseValues: []) == nil)
        #expect(GRICalculator.calculate(glucoseValues: [0, -1]) == nil)
        #expect(GRICalculator.calculate(glucoseValues: [0, -1, 100])?.score == 0)
    }

    @Test("Fixed thresholds classify their exact boundaries", arguments: [
        (53, 100.0, 0.0), (54, 80.0, 0.0), (69, 80.0, 0.0),
        (70, 0.0, 0.0), (180, 0.0, 0.0), (181, 0.0, 50.0),
        (250, 0.0, 50.0), (251, 0.0, 100.0)
    ]) func boundaries(sample: (Int, Double, Double)) throws {
        let result = try #require(GRICalculator.calculate(glucoseValues: [sample.0]))
        #expect(abs(result.hypoComponent - sample.1) < 0.000001)
        #expect(abs(result.hyperComponent - sample.2) < 0.000001)
    }

    @Test("Published worked example scores 79") func publishedExample() throws {
        // 5% very low, 10% low, 50% in range, 20% high, 15% very high.
        let values = [50] + Array(repeating: 60, count: 2) + Array(repeating: 100, count: 10)
            + Array(repeating: 200, count: 4) + Array(repeating: 300, count: 3)
        let result = try #require(GRICalculator.calculate(glucoseValues: values))
        #expect(abs(result.score - 79) < 0.000001)
        #expect(abs(result.hypoComponent - 13) < 0.000001)
        #expect(abs(result.hyperComponent - 25) < 0.000001)
        #expect(result.veryLowPercentage == 5)
        #expect(result.lowPercentage == 10)
        #expect(result.highPercentage == 20)
        #expect(result.veryHighPercentage == 15)
        #expect(result.weightedHypoComponent == 39)
        #expect(result.weightedHyperComponent == 40)
        #expect(result.uncappedScore == 79)
        #expect(result.zone == "D")
    }

    @Test("Extreme results cap the score but preserve components") func cap() throws {
        let result = try #require(GRICalculator.calculate(glucoseValues: [40, 40]))
        #expect(result.score == 100)
        #expect(result.hypoComponent == 100)
        #expect(result.uncappedScore == 300)
        #expect(result.zone == "E")
        #expect(GRICalculator.calculate(glucoseValues: [300])?.score == 100)
    }

    @Test("A period is weighted by readings, not daily scores") func weighting() throws {
        let values = [50] + Array(repeating: 100, count: 99)
        let result = try #require(GRICalculator.calculate(glucoseValues: values))
        #expect(result.score == 3)
    }

    @Test("Zones use unrounded scores", arguments: [
        (0.0, "A"), (20.0, "A"), (20.01, "B"), (40.0, "B"), (40.01, "C"),
        (60.0, "C"), (60.01, "D"), (80.0, "D"), (80.01, "E"), (100.0, "E")
    ]) func zones(sample: (Double, String)) {
        #expect(GRICalculator.Result(
            veryLowPercentage: 0,
            lowPercentage: 0,
            highPercentage: 0,
            veryHighPercentage: sample.0 / 1.6
        ).zone == sample.1)
    }
}
