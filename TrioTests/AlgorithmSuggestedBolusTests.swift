import Foundation
import Testing
@testable import Trio

@Suite("Algorithm Suggested Bolus") struct AlgorithmSuggestedBolusTests {
    private func suggestion(insulinRequired: Decimal, fraction: Decimal = 0.8, maxBolus: Decimal = 10) -> Decimal {
        let state = Treatments.StateModel()
        state.insulinRequired = insulinRequired
        state.fraction = fraction
        state.maxBolus = maxBolus
        return state.algorithmSuggestedBolus
    }

    @Test("Discounted by the Recommended Bolus Percentage") func appliesFraction() {
        #expect(suggestion(insulinRequired: 2) == 1.6)
        #expect(suggestion(insulinRequired: 2, fraction: 0.5) == 1)
    }

    @Test("Capped at Max Bolus") func respectsMaxBolus() {
        #expect(suggestion(insulinRequired: 100, maxBolus: 6) == 6)
    }

    @Test("Nothing to suggest when the algorithm wants no insulin") func nonPositiveRequirement() {
        #expect(suggestion(insulinRequired: 0) == 0)
        // oref returns a negative requirement when it wants basal reduced, which is not a bolus.
        #expect(suggestion(insulinRequired: -1.5) == 0)
    }
}
