import Foundation
import Testing

@testable import Trio

@Suite("Nightscout Import Round Trip Tests") struct NightscoutImportRoundTripTests {
    /// Mirrors the closest value matching in finalizeImport in
    /// OnboardingStateModel+Nightscout.swift.
    private func closestIndex(for value: Decimal, in rateValues: [Decimal]) -> Int {
        rateValues.enumerated().min(by: {
            abs($0.element - value) < abs($1.element - value)
        })?.offset ?? 0
    }

    private func mmolStateModel() -> Onboarding.StateModel {
        let state = Onboarding.StateModel()
        state.units = .mmolL
        return state
    }

    @Test("every 0.1 mmol/L ISF value keeps its display value through import") func isfRoundTrip() {
        let rateValues = mmolStateModel().isfRateValues
        for tenths in 5 ... 300 {
            let mmol = Decimal(tenths) / 10
            let imported = mmol.asMgdL
            let matched = rateValues[closestIndex(for: imported, in: rateValues)]
            #expect(
                matched.asMmolL == mmol,
                "ISF \(mmol) mmol/L imported as \(matched) mg/dL, shown as \(matched.asMmolL)"
            )
        }
    }

    @Test("every 0.1 mmol/L target value keeps its display value through import") func targetRoundTrip() {
        let rateValues = mmolStateModel().targetRateValues
        for tenths in 40 ... 100 {
            let mmol = Decimal(tenths) / 10
            let imported = mmol.asMgdL
            let matched = rateValues[closestIndex(for: imported, in: rateValues)]
            #expect(
                matched.asMmolL == mmol,
                "target \(mmol) mmol/L imported as \(matched) mg/dL, shown as \(matched.asMmolL)"
            )
        }
    }

    @Test("ISF 5.6 mmol/L matches the 5.6 picker entry, not 5.7") func isf56FromIssue1179() {
        let rateValues = mmolStateModel().isfRateValues
        let mmol = Decimal(56) / 10
        let imported = mmol.asMgdL
        #expect(imported == 101)
        let matched = rateValues[closestIndex(for: imported, in: rateValues)]
        #expect(matched == 100)
        #expect(matched.asMmolL == mmol)
    }

    @Test("mmol/L ISF picker holds exactly one entry per 0.1 step") func isfPickerSteps() {
        let displays = mmolStateModel().isfRateValues.map(\.asMmolL)
        #expect(displays == (5 ... 300).map { Decimal($0) / 10 })
    }

    @Test("mmol/L target picker holds exactly one entry per 0.1 step") func targetPickerSteps() {
        let displays = mmolStateModel().targetRateValues.map(\.asMmolL)
        #expect(displays == (40 ... 100).map { Decimal($0) / 10 })
    }

    @Test("mg/dL ISF values import unchanged") func mgdlIdentity() {
        let rateValues = Onboarding.StateModel().isfRateValues
        #expect(rateValues == (9 ... 540).map { Decimal($0) })
        for value: Decimal in [41, 54, 100, 101, 102, 240, 540] {
            let matched = rateValues[closestIndex(for: value, in: rateValues)]
            #expect(matched == value)
        }
    }
}
