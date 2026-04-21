import Foundation
import Testing

@testable import Trio

@Suite("Bolus Safety Validator Tests") struct BolusSafetyValidatorTests: Injectable {
    @Injected() var validator: BolusSafetyValidator!
    let resolver = TrioApp().resolver

    init() {
        injectServices(resolver)
    }

    @Test("Validator resolves from the service container") func testValidatorResolves() {
        #expect(validator != nil, "BolusSafetyValidator should be registered in ServiceAssembly")
        #expect(validator is BaseBolusSafetyValidator, "Validator should be of type BaseBolusSafetyValidator")
    }

    @Test("Allows bolus when all inputs are within limits") func testAllowed() {
        let inputs = BolusSafetyInputs(
            maxBolus: 10,
            maxIOB: 10,
            currentIOB: 1,
            totalRecentBolus: 0
        )
        #expect(BolusSafetyEvaluator.evaluate(bolusAmount: 5, inputs: inputs) == .allowed)
    }

    @Test("Rejects when amount exceeds max bolus") func testExceedsMaxBolus() {
        let inputs = BolusSafetyInputs(
            maxBolus: 5,
            maxIOB: 10,
            currentIOB: 0,
            totalRecentBolus: 0
        )
        let result = BolusSafetyEvaluator.evaluate(bolusAmount: 6, inputs: inputs)
        #expect(result == .rejected(.exceedsMaxBolus(maxBolus: 5)))
    }

    @Test("Rejects when current IOB is unavailable") func testIOBUnavailable() {
        let inputs = BolusSafetyInputs(
            maxBolus: 10,
            maxIOB: 10,
            currentIOB: nil,
            totalRecentBolus: 0
        )
        let result = BolusSafetyEvaluator.evaluate(bolusAmount: 1, inputs: inputs)
        #expect(result == .rejected(.iobUnavailable))
    }

    @Test("Rejects when amount would exceed max IOB") func testExceedsMaxIOB() {
        let inputs = BolusSafetyInputs(
            maxBolus: 10,
            maxIOB: 5,
            currentIOB: 3,
            totalRecentBolus: 0
        )
        let result = BolusSafetyEvaluator.evaluate(bolusAmount: 2.5, inputs: inputs)
        #expect(result == .rejected(.exceedsMaxIOB(currentIOB: 3, maxIOB: 5)))
    }

    @Test("Rejects when recent bolus totals >= 20% of requested amount") func testRecentBolusWithinWindow() {
        let inputs = BolusSafetyInputs(
            maxBolus: 10,
            maxIOB: 10,
            currentIOB: 0,
            totalRecentBolus: 1.0
        )
        let result = BolusSafetyEvaluator.evaluate(bolusAmount: 5, inputs: inputs)
        #expect(result == .rejected(.recentBolusWithinWindow(totalRecent: 1.0)))
    }

    @Test("Allows when recent bolus total is below 20% threshold") func testRecentBolusBelowThreshold() {
        let inputs = BolusSafetyInputs(
            maxBolus: 10,
            maxIOB: 10,
            currentIOB: 0,
            totalRecentBolus: 0.99
        )
        #expect(BolusSafetyEvaluator.evaluate(bolusAmount: 5, inputs: inputs) == .allowed)
    }

    @Test("Max bolus check runs before IOB check") func testCheckOrdering() {
        let inputs = BolusSafetyInputs(
            maxBolus: 5,
            maxIOB: 10,
            currentIOB: nil,
            totalRecentBolus: 0
        )
        let result = BolusSafetyEvaluator.evaluate(bolusAmount: 6, inputs: inputs)
        #expect(result == .rejected(.exceedsMaxBolus(maxBolus: 5)))
    }

    @Test("Equal-to-max-bolus is allowed") func testEqualsMaxBolus() {
        let inputs = BolusSafetyInputs(
            maxBolus: 5,
            maxIOB: 10,
            currentIOB: 0,
            totalRecentBolus: 0
        )
        #expect(BolusSafetyEvaluator.evaluate(bolusAmount: 5, inputs: inputs) == .allowed)
    }

    @Test("Current IOB plus amount equal to max IOB is allowed") func testEqualToMaxIOB() {
        let inputs = BolusSafetyInputs(
            maxBolus: 10,
            maxIOB: 5,
            currentIOB: 3,
            totalRecentBolus: 0
        )
        #expect(BolusSafetyEvaluator.evaluate(bolusAmount: 2, inputs: inputs) == .allowed)
    }
}
