import Foundation
import Testing

@testable import Trio

@Suite("Trio Alerts: ForecastedGlucoseEvaluator") struct ForecastedGlucoseEvaluatorTests {
    /// Builds a `Determination` defaulting every non-predictions field, varying only `predictions`.
    private func makeDetermination(predictions: Predictions?) -> Determination {
        Determination(
            id: nil,
            reason: "",
            units: nil,
            insulinReq: nil,
            eventualBG: nil,
            sensitivityRatio: nil,
            rate: nil,
            duration: nil,
            iob: nil,
            cob: nil,
            predictions: predictions,
            deliverAt: nil,
            carbsReq: nil,
            temp: nil,
            bg: nil,
            reservoir: nil,
            isf: nil,
            timestamp: nil,
            tdd: nil,
            current_target: nil,
            minDelta: nil,
            expectedDelta: nil,
            minGuardBG: nil,
            minPredBG: nil,
            threshold: nil,
            carbRatio: nil,
            received: nil
        )
    }

    @Test("Reduces to min across all four curves at default horizon (+20min, index 4)") func minAcrossAllFourCurves() {
        let predictions = Predictions(
            iob: [100, 101, 102, 103, 104],
            zt: [130, 131, 132, 133, 99],
            cob: [110, 111, 112, 113, 90],
            uam: [120, 121, 122, 123, 95]
        )
        let determination = makeDetermination(predictions: predictions)

        let result = ForecastedGlucoseEvaluator.evaluate(determination: determination)
        #expect(result != nil)
        #expect(result?.predictedGlucose == Decimal(90))
        #expect(result?.horizonMinutes == 20)
        #expect(result?.curvesUsed == Set([.iob, .cob, .uam, .zt]))
        #expect(result?.perCurve[.iob] == Decimal(104))
        #expect(result?.perCurve[.cob] == Decimal(90))
        #expect(result?.perCurve[.uam] == Decimal(95))
        #expect(result?.perCurve[.zt] == Decimal(99))
    }

    @Test("nil predictions returns nil") func nilPredictionsReturnsNil() {
        let determination = makeDetermination(predictions: nil)
        #expect(ForecastedGlucoseEvaluator.evaluate(determination: determination) == nil)
    }

    @Test("All curves shorter than the horizon index returns nil") func indexOutOfBoundsAllShortReturnsNil() {
        let predictions = Predictions(
            iob: [100, 101, 102],
            zt: [130, 131, 132],
            cob: [110, 111, 112],
            uam: [120, 121, 122]
        )
        let determination = makeDetermination(predictions: predictions)
        #expect(ForecastedGlucoseEvaluator.evaluate(determination: determination) == nil)
    }

    @Test("Only one populated curve is used") func onlyOneCurvePopulated() {
        let predictions = Predictions(
            iob: [80, 81, 82, 83, 84],
            zt: nil,
            cob: nil,
            uam: nil
        )
        let determination = makeDetermination(predictions: predictions)

        let result = ForecastedGlucoseEvaluator.evaluate(determination: determination)
        #expect(result != nil)
        #expect(result?.predictedGlucose == Decimal(84))
        #expect(result?.curvesUsed == Set([.iob]))
    }

    @Test("Non-default horizon selects the matching index") func nonDefaultHorizonSelectsCorrectIndex() {
        let predictions = Predictions(
            iob: [100, 90, 80, 70],
            zt: nil,
            cob: [105, 95, 85, 75],
            uam: nil
        )
        let determination = makeDetermination(predictions: predictions)

        let result = ForecastedGlucoseEvaluator.evaluate(determination: determination, horizonMinutes: 10)
        #expect(result != nil)
        #expect(result?.predictedGlucose == Decimal(80))
        #expect(result?.curvesUsed == Set([.iob, .cob]))
        #expect(result?.horizonMinutes == 10)
    }

    @Test("Curves with differing lengths skip those missing the index") func differingLengthsSomeMissing() {
        let predictions = Predictions(
            iob: [100, 101, 102, 103, 104],
            zt: [130, 131, 132],
            cob: [110, 111],
            uam: [120, 121, 122, 123, 70]
        )
        let determination = makeDetermination(predictions: predictions)

        let result = ForecastedGlucoseEvaluator.evaluate(determination: determination)
        #expect(result != nil)
        #expect(result?.predictedGlucose == Decimal(70))
        #expect(result?.curvesUsed == Set([.iob, .uam]))
    }

    @Test("All-empty arrays return nil") func emptyArraysReturnNil() {
        let predictions = Predictions(iob: [], zt: [], cob: [], uam: [])
        let determination = makeDetermination(predictions: predictions)
        #expect(ForecastedGlucoseEvaluator.evaluate(determination: determination) == nil)
    }
}
