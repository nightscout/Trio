import Foundation
import LoopKit
import Testing

@testable import Trio

@Suite("Pre-Bolus Recommendation Tests") struct PreBolusRecommendationTests {
    private let target: Decimal = 110

    private func evaluate(
        currentBG: Decimal,
        deltaBG: Decimal = 0,
        direction: BloodGlucose.Direction? = .flat,
        carbs: Decimal = 0,
        fat: Decimal = 0,
        protein: Decimal = 0,
        insulinType: InsulinType? = nil,
        fatAndProteinTracked: Bool = false,
        isGlucoseFresh: Bool = true
    ) -> PreBolusRecommendation {
        PreBolusRecommendation.evaluate(
            currentBG: currentBG,
            deltaBG: deltaBG,
            target: target,
            direction: direction,
            carbs: carbs,
            fat: fat,
            protein: protein,
            insulinType: insulinType,
            fatAndProteinTracked: fatAndProteinTracked,
            isGlucoseFresh: isGlucoseFresh
        )
    }

    // MARK: - Stage 1: the safety gate

    @Test("Stale glucose: no lead, bolus with the first bite") func testStaleGlucose() {
        let result = evaluate(currentBG: 110, carbs: 40, isGlucoseFresh: false)

        #expect(result.minutes == 0)
        #expect(result.isGated)
        #expect(!result.isBelowLowThreshold)
    }

    @Test("Below 70 mg/dL: treat the low, no pre-bolus") func testBelowLowThreshold() {
        let result = evaluate(currentBG: 63, carbs: 40)

        #expect(result.minutes == 0)
        #expect(result.isBelowLowThreshold)
        #expect(result.isGated)
    }

    @Test("Below target: no lead, bolus with the first bite") func testBelowTarget() {
        let result = evaluate(currentBG: 90, carbs: 20)

        #expect(result.minutes == 0)
        #expect(result.isGated)
        #expect(!result.isBelowLowThreshold)
    }

    @Test("Falling arrow overrides an at-target reading") func testFallingArrow() {
        for direction in [BloodGlucose.Direction.fortyFiveDown, .singleDown, .doubleDown, .tripleDown] {
            #expect(evaluate(currentBG: 110, direction: direction, carbs: 20).minutes == 0, "\(direction)")
        }
    }

    @Test("Falling numeric delta gates when the arrow is missing or flat") func testFallingDelta() {
        // −15 over the ~20 min window is 0.75 mg/dL/min: still a flat arrow on every CGM, but
        // enough to stop giving insulin a head start.
        #expect(evaluate(currentBG: 110, deltaBG: -15, direction: nil, carbs: 20).minutes == 0)
        #expect(evaluate(currentBG: 110, deltaBG: -15, direction: .flat, carbs: 20).minutes == 0)
        #expect(evaluate(currentBG: 110, deltaBG: -30, direction: nil, carbs: 20).minutes == 0)
    }

    @Test("Sensor-noise sized dips do not gate") func testSmallDeltaIsNotFalling() {
        // −8 over 20 min is 0.4 mg/dL/min: inside the flat band and well within sensor noise.
        // Gating on this would suppress most steady at-target meals.
        let result = evaluate(currentBG: 110, deltaBG: -8, direction: .flat, carbs: 20)

        #expect(!result.isGated)
        #expect(result.minutes == 15)
        #expect(!evaluate(currentBG: 110, deltaBG: -14, direction: nil, carbs: 20).isGated)
    }

    @Test("The gate beats even the fastest meal") func testGateBeatsMealSpeed() {
        let result = evaluate(currentBG: 90, carbs: 80)

        #expect(result.minutes == 0)
        #expect(result.baseMinutes == 0, "the gate short-circuits before the meal is looked at")
    }

    // MARK: - Stage 2: base lead from meal speed

    @Test("Explicitly logged fast carbs: 20 min base") func testFastCarbBase() {
        let result = evaluate(currentBG: 110, carbs: 40, fatAndProteinTracked: true)

        #expect(result.baseMinutes == 20)
        #expect(result.minutes == 20)
    }

    @Test("Plain carbs without fat/protein tracking are a normal meal, not fast carbs") func testUntrackedCarbsAreNotFast() {
        // Without fat/protein entry, fat == 0 && protein == 0 means "not entered". Assuming fast
        // carbs would over-lead the ordinary meals most users log.
        #expect(evaluate(currentBG: 110, carbs: 40).baseMinutes == 15)
        // Even a large carb load.
        #expect(evaluate(currentBG: 110, carbs: 90).baseMinutes == 15)
    }

    @Test("Anything not pure fast carbs: 15 min base") func testMixedMealBase() {
        let result = evaluate(currentBG: 110, carbs: 60, fat: 8, protein: 6, fatAndProteinTracked: true)

        #expect(result.baseMinutes == 15)
        #expect(result.minutes == 15)
    }

    @Test("Fat never shortens the lead below the standard base") func testFatDoesNotShorten() {
        // Fat and protein are covered later as delayed carb equivalents, so shortening the lead
        // for them would count that delay twice and under-lead the carbs.
        let plate = evaluate(currentBG: 110, carbs: 80, fat: 5, protein: 5)
        let pizza = evaluate(currentBG: 110, carbs: 80, fat: 30, protein: 25)
        let veryFatty = evaluate(currentBG: 110, carbs: 80, fat: 90, protein: 60)

        #expect(pizza.baseMinutes == plate.baseMinutes)
        #expect(veryFatty.baseMinutes == plate.baseMinutes)
        #expect(pizza.minutes == 15)
    }

    @Test("A small carb entry is a mixed meal, not fast carbs") func testSmallCarbsAreNotFast() {
        #expect(evaluate(currentBG: 110, carbs: 15).baseMinutes == 15)
    }

    // MARK: - Stage 2b: insulin onset speed

    @Test("Ultra-rapid insulins shorten every base by 5 min") func testUltraRapidShortensBase() {
        let rapidFast = evaluate(currentBG: 110, carbs: 40, fatAndProteinTracked: true)
        let rapidMixed = evaluate(currentBG: 110, carbs: 60, fat: 8, protein: 6)
        #expect(rapidFast.baseMinutes == 20)
        #expect(rapidMixed.baseMinutes == 15)

        for insulin in [InsulinType.lyumjev, .fiasp] {
            let fast = evaluate(currentBG: 110, carbs: 40, insulinType: insulin, fatAndProteinTracked: true)
            let mixed = evaluate(currentBG: 110, carbs: 60, fat: 8, protein: 6, insulinType: insulin)
            #expect(fast.baseMinutes == 15, "\(insulin)")
            #expect(mixed.baseMinutes == 10, "\(insulin)")
        }
    }

    @Test("The ultra-rapid saving is exposed as its own breakdown line") func testInsulinAdjustmentBreakdown() {
        let rapid = evaluate(currentBG: 110, carbs: 45, fat: 10, protein: 8)
        #expect(rapid.mealBase == 15)
        #expect(rapid.insulinAdjustment == 0)
        #expect(rapid.insulinAdjustmentReason == nil)
        #expect(rapid.baseMinutes == 15)

        for insulin in [InsulinType.fiasp, .lyumjev] {
            let ultraRapid = evaluate(currentBG: 110, carbs: 45, fat: 10, protein: 8, insulinType: insulin)
            #expect(ultraRapid.mealBase == 15, "\(insulin)")
            #expect(ultraRapid.insulinAdjustment == -5, "\(insulin)")
            #expect(ultraRapid.baseMinutes == 10, "\(insulin)")
            #expect(ultraRapid.insulinAdjustmentReason != nil, "\(insulin)")
        }
    }

    @Test("Fiasp and Lyumjev share the ultra-rapid bases") func testFiaspMatchesLyumjev() {
        // Fiasp onsets roughly twice as fast as NovoRapid, the same shift Lyumjev shows over
        // Humalog. A few minutes separate the two, not a class.
        let fiasp = evaluate(currentBG: 110, carbs: 45, fat: 10, protein: 8, insulinType: .fiasp)
        let lyumjev = evaluate(currentBG: 110, carbs: 45, fat: 10, protein: 8, insulinType: .lyumjev)

        #expect(fiasp.baseMinutes == lyumjev.baseMinutes)
        #expect(fiasp.minutes == lyumjev.minutes)
    }

    @Test("First-generation analogues all share the rapid bases") func testRapidActingBases() {
        for insulin in [InsulinType.novolog, .humalog, .apidra] {
            #expect(
                evaluate(currentBG: 110, carbs: 40, insulinType: insulin, fatAndProteinTracked: true).baseMinutes == 20,
                "\(insulin)"
            )
            #expect(evaluate(currentBG: 110, carbs: 60, fat: 8, protein: 6, insulinType: insulin).baseMinutes == 15, "\(insulin)")
        }
    }

    @Test("Insulin speed does not change the glucose adjustment") func testInsulinSpeedKeepsAdjustment() {
        let rapid = evaluate(currentBG: 148, carbs: 20)
        let lyumjev = evaluate(currentBG: 148, carbs: 20, insulinType: .lyumjev)

        #expect(rapid.adjustment == lyumjev.adjustment)
        #expect(rapid.minutes == 20)
        #expect(lyumjev.minutes == 15)
    }

    @Test("Unknown insulin type assumes rapid-acting") func testUnknownInsulinAssumesRapidActing() {
        let defaulted = PreBolusRecommendation.evaluate(
            currentBG: 110,
            deltaBG: 0,
            target: target,
            direction: .flat,
            carbs: 20,
            fat: 0,
            protein: 0
        )

        #expect(defaulted.baseMinutes == 15)
    }

    // MARK: - Stage 3: the glucose adjustment

    @Test("At target and steady: no adjustment") func testAtTargetSteady() {
        #expect(evaluate(currentBG: 110, carbs: 20).adjustment == 0)
        // The ±10 mg/dL band still counts as "at target".
        #expect(evaluate(currentBG: 118, carbs: 20).adjustment == 0)
        #expect(evaluate(currentBG: 102, carbs: 20).adjustment == 0)
    }

    @Test("Above target: +5 min") func testAboveTarget() {
        #expect(evaluate(currentBG: 148, carbs: 20).adjustment == 5)
    }

    @Test("Well above target: +10 min") func testWellAboveTarget() {
        #expect(evaluate(currentBG: 171, carbs: 20).adjustment == 10)
    }

    // MARK: - Stage 3b: the trend adjustment

    @Test("Rising arrow at target: +5 min") func testRisingArrowAtTarget() {
        for direction in [BloodGlucose.Direction.fortyFiveUp, .singleUp, .doubleUp, .tripleUp] {
            let result = evaluate(currentBG: 110, direction: direction, carbs: 20)
            #expect(result.adjustment == 5, "\(direction)")
            #expect(result.minutes == 20, "\(direction)")
        }
    }

    @Test("Rising stacks on the level adjustment") func testRisingStacksOnLevel() {
        #expect(evaluate(currentBG: 148, direction: .fortyFiveUp, carbs: 20).adjustment == 10)
        #expect(evaluate(currentBG: 171, direction: .singleUp, carbs: 20).adjustment == 15)
        // Still bounded by the ceiling.
        #expect(evaluate(currentBG: 171, direction: .singleUp, carbs: 20).minutes == 25)
    }

    @Test("Rising numeric delta stands in only when the arrow is missing") func testRisingDeltaFallback() {
        // No arrow: the delta decides.
        #expect(evaluate(currentBG: 110, deltaBG: 15, direction: nil, carbs: 20).adjustment == 5)
        #expect(evaluate(currentBG: 110, deltaBG: 14, direction: nil, carbs: 20).adjustment == 0)
        // Flat arrow: the arrow is authoritative, the delta is ignored.
        #expect(evaluate(currentBG: 110, deltaBG: 30, direction: .flat, carbs: 20).adjustment == 0)
    }

    // MARK: - Worked examples

    @Test("Sandwich at target: 15 min") func testSandwichAtTarget() {
        #expect(evaluate(currentBG: 110, carbs: 45, fat: 10, protein: 8).minutes == 15)
    }

    @Test("Sandwich at target on Lyumjev: 10 min") func testSandwichAtTargetLyumjev() {
        #expect(evaluate(currentBG: 110, carbs: 45, fat: 10, protein: 8, insulinType: .lyumjev).minutes == 10)
    }

    @Test("Sandwich at target on Fiasp: 10 min") func testSandwichAtTargetFiasp() {
        #expect(evaluate(currentBG: 110, carbs: 45, fat: 10, protein: 8, insulinType: .fiasp).minutes == 10)
    }

    @Test("Sandwich at target but rising: 20 min") func testSandwichRising() {
        #expect(evaluate(currentBG: 110, direction: .fortyFiveUp, carbs: 45, fat: 10, protein: 8).minutes == 20)
    }

    @Test("Sandwich well above target: 25 min") func testSandwichWellAbove() {
        #expect(evaluate(currentBG: 171, carbs: 45, fat: 10, protein: 8).minutes == 25)
    }

    @Test("Pizza above target: 20 min") func testPizzaAboveTarget() {
        #expect(evaluate(currentBG: 148, carbs: 80, fat: 30, protein: 25).minutes == 20)
    }

    @Test("Juice well above target: capped at 25 min") func testJuiceWellAboveIsCapped() {
        let result = evaluate(currentBG: 171, carbs: 40, fatAndProteinTracked: true)

        #expect(result.uncappedMinutes == 30)
        #expect(result.minutes == 25)
    }

    @Test("Juice well above target and rising: capped at 25 min") func testJuiceWellAboveRisingIsCapped() {
        let result = evaluate(currentBG: 171, direction: .singleUp, carbs: 40, fatAndProteinTracked: true)

        #expect(result.uncappedMinutes == 35)
        #expect(result.minutes == 25)
    }

    // MARK: - Edges

    @Test("Result never exceeds the ceiling") func testNeverExceedsCeiling() {
        let directions: [BloodGlucose.Direction?] = [nil, .flat, .fortyFiveUp, .doubleUp]
        for bg in stride(from: 50, through: 400, by: 5) {
            for fat in stride(from: 0, through: 60, by: 10) {
                for direction in directions {
                    let result = evaluate(currentBG: Decimal(bg), direction: direction, carbs: 45, fat: Decimal(fat))
                    #expect(
                        (0 ... PreBolusRecommendation.Config.maxMinutes).contains(result.minutes),
                        "bg \(bg), fat \(fat), \(String(describing: direction)) → \(result.minutes)"
                    )
                }
            }
        }
    }

    @Test("A zero glucose reading is treated as unknown, not as a low") func testZeroGlucoseIsNotLow() {
        let result = evaluate(currentBG: 0, carbs: 40)

        #expect(!result.isBelowLowThreshold)
        #expect(!result.isGated, "no reading is not a reason to suppress the suggestion")
    }

    @Test("A missing target falls back to 110 mg/dL") func testTargetFallback() {
        let result = PreBolusRecommendation.evaluate(
            currentBG: 110,
            deltaBG: 0,
            target: 0,
            direction: .flat,
            carbs: 20,
            fat: 0,
            protein: 0
        )

        #expect(result.adjustment == 0, "110 mg/dL should read as at-target against the 110 mg/dL default")
    }

    @Test("The one-line reason survives a gate and a full breakdown") func testReasonText() {
        #expect(evaluate(currentBG: 63, carbs: 40).reason.contains("low"))

        let fatty = evaluate(currentBG: 148, carbs: 80, fat: 30, protein: 25)
        #expect(fatty.reason.contains("Mixed meal"))
        #expect(fatty.reason.contains("Above target"))

        let rising = evaluate(currentBG: 110, direction: .fortyFiveUp, carbs: 20)
        #expect(rising.reason.contains("rising"))

        let highAndRising = evaluate(currentBG: 148, direction: .fortyFiveUp, carbs: 20)
        #expect(highAndRising.reason.contains("Above target"))
        #expect(highAndRising.reason.contains("Rising"))
    }
}
