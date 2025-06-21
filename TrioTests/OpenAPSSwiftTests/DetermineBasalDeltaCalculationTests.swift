import Foundation
import Testing
@testable import Trio

@Suite("Determination: Expected Delta Calculation Tests") struct ExpectedDeltaTests {
    /// When delta is smaller than one 5-min block, only glucoseImpact is returned.
    @Test("no change when delta < 24 blocks") func deltaSmallerThanBlock() {
        let result = DeterminationGenerator.calculateExpectedDelta(
            targetGlucose: Decimal(120),
            eventualGlucose: Decimal(100),
            glucoseImpact: Decimal(2)
        )
        // delta = 20; Int(20)/24 = 0 → result = 2 + 0 = 2.0
        #expect(result == Decimal(2.0))
    }

    /// When delta spans exactly one block, adds 1 to glucoseImpact.
    @Test("one block delta") func deltaExactlyOneBlock() {
        let result = DeterminationGenerator.calculateExpectedDelta(
            targetGlucose: Decimal(124),
            eventualGlucose: Decimal(100),
            glucoseImpact: Decimal(1.5)
        )
        // delta = 24; Int(24)/24 = 1 → result = 1.5 + 1 = 2.5
        #expect(result == Decimal(2.5))
    }

    /// When delta spans multiple blocks, uses integer division.
    @Test("multi-block delta") func deltaMultipleBlocks() {
        let result = DeterminationGenerator.calculateExpectedDelta(
            targetGlucose: Decimal(140),
            eventualGlucose: Decimal(100),
            glucoseImpact: Decimal(0)
        )
        // delta = 40; Int(40)/24 = 1 → result = 0 + 1 = 1.0
        #expect(result == Decimal(1.0))
    }

    /// Negative delta yields negative adjustment when blocks exceed delta.
    @Test("negative delta") func negativeDelta() {
        let result = DeterminationGenerator.calculateExpectedDelta(
            targetGlucose: Decimal(80),
            eventualGlucose: Decimal(100),
            glucoseImpact: Decimal(0)
        )
        // delta = -20; Int(-20)/24 = 0 (trunc toward zero) → result = 0 + 0 = 0.0
        #expect(result == Decimal(0.0))
    }

    /// Fractional delta is truncated before block division.
    @Test("fractional delta truncation") func fractionalDelta() {
        let result = DeterminationGenerator.calculateExpectedDelta(
            targetGlucose: Decimal(string: "125.5")!,
            eventualGlucose: Decimal(100),
            glucoseImpact: Decimal(0)
        )
        // delta = 25.5; Int(25.5)=25; 25/24=1 → result = 1.0
        #expect(result == Decimal(1.0))
    }

    /// Rounding to one decimal place works when glucoseImpact has two decimals.
    @Test("rounding one decimal place") func roundingOneDecimal() {
        let result = DeterminationGenerator.calculateExpectedDelta(
            targetGlucose: Decimal(124),
            eventualGlucose: Decimal(100),
            glucoseImpact: Decimal(string: "1.27")!
        )
        // delta=24 → blocks=1; adjustment=1; 1.27+1=2.27 → rounded to 2.3
        #expect(result == Decimal(string: "2.3")!)
    }

    /// Extreme high eventual glucose produces a large negative expected delta.
    @Test("extreme high eventual glucose") func extremeHighEventual() {
        let result = DeterminationGenerator.calculateExpectedDelta(
            targetGlucose: Decimal(120),
            eventualGlucose: Decimal(350),
            glucoseImpact: Decimal(0)
        )
        // delta = 120 - 350 = -230; Int(-230)/24 = -9 → result = 0 + (-9) = -9.0
        #expect(result == Decimal(string: "-9.0")!)
    }

    /// Extreme low eventual glucose produces a positive expected delta.
    @Test("extreme low eventual glucose") func extremeLowEventual() {
        let result = DeterminationGenerator.calculateExpectedDelta(
            targetGlucose: Decimal(120),
            eventualGlucose: Decimal(39),
            glucoseImpact: Decimal(0)
        )
        // delta = 81; Int(81)/24 = 3 → result = 0 + 3 = 3.0
        #expect(result == Decimal(string: "3.0")!)
    }

    /// Invalid low‐unit input (<39 mg/dL) falls back to only using glucoseImpact.
    @Test("invalid low input treated as only impact") func invalidLowInput() {
        let result = DeterminationGenerator.calculateExpectedDelta(
            targetGlucose: Decimal(5), // e.g. mmol/L mistakenly passed
            eventualGlucose: Decimal(3),
            glucoseImpact: Decimal(string: "1.7")!
        )
        // delta = 2; Int(2)/24 = 0 → result = 1.7 + 0 = 1.7
        #expect(result == Decimal(string: "1.7")!)
    }
}
