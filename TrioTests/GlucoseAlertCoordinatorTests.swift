import Foundation
import Testing

@testable import Trio

@Suite("Trio Alerts: GlucoseAlertCoordinator breach/retract") struct GlucoseAlertCoordinatorTests {
    @Test("low breaches at or below threshold 70") func lowBreach() {
        #expect(GlucoseAlertCoordinator.breached(type: .low, latestMgDL: 70, thresholdMgDL: 70))
        #expect(!GlucoseAlertCoordinator.breached(type: .low, latestMgDL: 71, thresholdMgDL: 70))
    }

    @Test("low retracts only at threshold + margin (70 + 5)") func lowRetract() {
        #expect(!GlucoseAlertCoordinator.shouldRetract(
            type: .low, latestMgDL: 74, thresholdMgDL: 70, recoveryMarginMgDL: 5
        ))
        #expect(GlucoseAlertCoordinator.shouldRetract(
            type: .low, latestMgDL: 75, thresholdMgDL: 70, recoveryMarginMgDL: 5
        ))
    }

    @Test("urgentLow breaches at or below threshold 54") func urgentLowBreach() {
        #expect(GlucoseAlertCoordinator.breached(type: .urgentLow, latestMgDL: 54, thresholdMgDL: 54))
        #expect(!GlucoseAlertCoordinator.breached(type: .urgentLow, latestMgDL: 55, thresholdMgDL: 54))
    }

    @Test("high breaches at or above threshold 270") func highBreach() {
        #expect(GlucoseAlertCoordinator.breached(type: .high, latestMgDL: 270, thresholdMgDL: 270))
        #expect(!GlucoseAlertCoordinator.breached(type: .high, latestMgDL: 269, thresholdMgDL: 270))
    }

    @Test("high retracts only at threshold - margin (270 - 5)") func highRetract() {
        #expect(!GlucoseAlertCoordinator.shouldRetract(
            type: .high, latestMgDL: 266, thresholdMgDL: 270, recoveryMarginMgDL: 5
        ))
        #expect(GlucoseAlertCoordinator.shouldRetract(
            type: .high, latestMgDL: 265, thresholdMgDL: 270, recoveryMarginMgDL: 5
        ))
    }

    @Test("type priority order: urgentLow < low < forecastedLow < high") func priorityOrder() {
        #expect(GlucoseAlertType.urgentLow.priority == 0)
        #expect(GlucoseAlertType.low.priority == 1)
        #expect(GlucoseAlertType.forecastedLow.priority == 2)
        #expect(GlucoseAlertType.high.priority == 3)
        #expect(GlucoseAlertType.urgentLow.priority < GlucoseAlertType.low.priority)
    }

    @Test("shouldRetract uses the default 5 mg/dL margin when omitted") func defaultMarginWiring() {
        #expect(GlucoseAlertCoordinator.shouldRetract(type: .low, latestMgDL: 75, thresholdMgDL: 70))
        #expect(!GlucoseAlertCoordinator.shouldRetract(type: .low, latestMgDL: 74, thresholdMgDL: 70))
    }
}
