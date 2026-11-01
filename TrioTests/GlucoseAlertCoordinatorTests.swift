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

    @Test(
        "type priority order: urgentLow < low < fallingFast < forecastedLow < high < risingFast < carbsRequired"
    ) func priorityOrder() {
        #expect(GlucoseAlertType.urgentLow.priority == 0)
        #expect(GlucoseAlertType.low.priority == 1)
        #expect(GlucoseAlertType.fallingFast.priority == 2)
        #expect(GlucoseAlertType.forecastedLow.priority == 3)
        #expect(GlucoseAlertType.high.priority == 4)
        #expect(GlucoseAlertType.risingFast.priority == 5)
        #expect(GlucoseAlertType.carbsRequired.priority == 6)
        #expect(GlucoseAlertType.urgentLow.priority < GlucoseAlertType.low.priority)
    }

    @Test("shouldRetract uses the default 5 mg/dL margin when omitted") func defaultMarginWiring() {
        #expect(GlucoseAlertCoordinator.shouldRetract(type: .low, latestMgDL: 75, thresholdMgDL: 70))
        #expect(!GlucoseAlertCoordinator.shouldRetract(type: .low, latestMgDL: 74, thresholdMgDL: 70))
    }

    // MARK: - Carbs Required predicates (mg/dL-based gates are no-ops)

    /// Carbs Required is determination-driven (`evaluateCarbsRequired(_:)`),
    /// not reading-driven. The shared mg/dL `breached` predicate must never
    /// return true for it, regardless of value / threshold combination.
    @Test("carbsRequired never breaches via the mg/dL predicate") func carbsRequiredNeverBreaches() {
        #expect(!GlucoseAlertCoordinator.breached(type: .carbsRequired, latestMgDL: 0, thresholdMgDL: 0))
        #expect(!GlucoseAlertCoordinator.breached(type: .carbsRequired, latestMgDL: 200, thresholdMgDL: 10))
        #expect(!GlucoseAlertCoordinator.breached(type: .carbsRequired, latestMgDL: 10, thresholdMgDL: 200))
    }

    @Test("carbsRequired never retracts via the mg/dL predicate") func carbsRequiredNeverRetractsViaMgDL() {
        #expect(!GlucoseAlertCoordinator.shouldRetract(
            type: .carbsRequired, latestMgDL: 100, thresholdMgDL: 10, recoveryMarginMgDL: 5
        ))
        #expect(!GlucoseAlertCoordinator.shouldRetract(
            type: .carbsRequired, latestMgDL: 0, thresholdMgDL: 50, recoveryMarginMgDL: 5
        ))
    }

    // MARK: - Falling / Rising Fast rate

    private static func readings(_ values: [Decimal], every minutes: Double) -> [(date: Date, glucose: Decimal)] {
        let now = Date()
        return values.enumerated().map { index, value in
            (date: now.addingTimeInterval(-Double(index) * minutes * 60), glucose: value)
        }
    }

    @Test("5-min readings: 45 mg/dL over 15 min is -3 mg/dL/min") func rateFiveMinuteCadence() {
        let rate = GlucoseAlertCoordinator.rateMgDLPerMinute(readings: Self.readings([100, 115, 130, 145], every: 5))
        #expect(rate == -3)
    }

    @Test("1-min readings use the oldest reading within 15 min") func rateOneMinuteCadence() {
        let values = (0 ... 20).map { Decimal(100 + 2 * $0) }
        let rate = GlucoseAlertCoordinator.rateMgDLPerMinute(readings: Self.readings(values, every: 1))
        #expect(rate == -2)
    }

    @Test("Fewer than 3 readings or a span under 10 min gives no rate") func rateNeedsEnoughData() {
        #expect(GlucoseAlertCoordinator.rateMgDLPerMinute(readings: Self.readings([100, 130], every: 10)) == nil)
        #expect(GlucoseAlertCoordinator.rateMgDLPerMinute(readings: Self.readings([100, 110, 120], every: 4)) == nil)
        #expect(GlucoseAlertCoordinator.rateMgDLPerMinute(readings: []) == nil)
    }

    @Test("5-min readings: rising 30 mg/dL over 15 min is +2 mg/dL/min") func rateRising() {
        let rate = GlucoseAlertCoordinator.rateMgDLPerMinute(readings: Self.readings([160, 150, 140, 130], every: 5))
        #expect(rate == 2)
    }

    @Test("No rate once a rise levels off") func rateNilAfterPeaking() {
        #expect(GlucoseAlertCoordinator.rateMgDLPerMinute(readings: Self.readings([155, 160, 140, 130], every: 5)) == nil)
    }

    @Test("No rate once the latest reading stops falling") func rateNilAfterBottomingOut() {
        #expect(GlucoseAlertCoordinator.rateMgDLPerMinute(readings: Self.readings([105, 100, 130, 145], every: 5)) == nil)
        #expect(GlucoseAlertCoordinator.rateMgDLPerMinute(readings: Self.readings([100, 100, 130, 145], every: 5)) == nil)
    }

    @Test("Gap: readings past the 15-min window are ignored") func rateIgnoresOldReadings() {
        let now = Date()
        let readings: [(date: Date, glucose: Decimal)] = [
            (now, 100), (now.addingTimeInterval(-5 * 60), 110), (now.addingTimeInterval(-10 * 60), 120),
            (now.addingTimeInterval(-25 * 60), 250)
        ]
        #expect(GlucoseAlertCoordinator.rateMgDLPerMinute(readings: readings) == -2)
    }

    @Test("Falling Fast breaches at or faster than the selected rate") func fallingFastBreach() {
        #expect(GlucoseAlertCoordinator.rateBreached(type: .fallingFast, rateMgDLPerMinute: -3, thresholdMgDLPerMinute: 3))
        #expect(!GlucoseAlertCoordinator.rateBreached(type: .fallingFast, rateMgDLPerMinute: -2.9, thresholdMgDLPerMinute: 3))
        #expect(!GlucoseAlertCoordinator.rateBreached(type: .fallingFast, rateMgDLPerMinute: 3, thresholdMgDLPerMinute: 3))
        #expect(!GlucoseAlertCoordinator.rateBreached(type: .fallingFast, rateMgDLPerMinute: nil, thresholdMgDLPerMinute: 2))
    }

    @Test("Rising Fast breaches at or faster than the selected rate") func risingFastBreach() {
        #expect(GlucoseAlertCoordinator.rateBreached(type: .risingFast, rateMgDLPerMinute: 2, thresholdMgDLPerMinute: 2))
        #expect(!GlucoseAlertCoordinator.rateBreached(type: .risingFast, rateMgDLPerMinute: 1.9, thresholdMgDLPerMinute: 2))
        #expect(!GlucoseAlertCoordinator.rateBreached(type: .risingFast, rateMgDLPerMinute: -3, thresholdMgDLPerMinute: 2))
    }

    @Test("Level types never breach on rate") func levelTypesIgnoreRate() {
        #expect(!GlucoseAlertCoordinator.rateBreached(type: .low, rateMgDLPerMinute: -10, thresholdMgDLPerMinute: 70))
        #expect(!GlucoseAlertCoordinator.rateBreached(type: .high, rateMgDLPerMinute: 10, thresholdMgDLPerMinute: 270))
    }

    @Test("Falling Fast retracts once the fall slows by 1 mg/dL/min or the rate is unknown") func fallingFastRetract() {
        #expect(!GlucoseAlertCoordinator.rateShouldRetract(type: .fallingFast, rateMgDLPerMinute: -2, thresholdMgDLPerMinute: 3))
        #expect(GlucoseAlertCoordinator.rateShouldRetract(type: .fallingFast, rateMgDLPerMinute: -1.9, thresholdMgDLPerMinute: 3))
        #expect(GlucoseAlertCoordinator.rateShouldRetract(type: .fallingFast, rateMgDLPerMinute: nil, thresholdMgDLPerMinute: 3))
    }

    @Test("Rising Fast retracts once the rise slows by 1 mg/dL/min or the rate is unknown") func risingFastRetract() {
        #expect(!GlucoseAlertCoordinator.rateShouldRetract(type: .risingFast, rateMgDLPerMinute: 2, thresholdMgDLPerMinute: 3))
        #expect(GlucoseAlertCoordinator.rateShouldRetract(type: .risingFast, rateMgDLPerMinute: 1.9, thresholdMgDLPerMinute: 3))
        #expect(GlucoseAlertCoordinator.rateShouldRetract(type: .risingFast, rateMgDLPerMinute: nil, thresholdMgDLPerMinute: 3))
    }

    @Test("Rate alarms never breach or retract via the mg/dL predicates") func rateTypesIgnoreLevelPredicates() {
        for type in [GlucoseAlertType.fallingFast, .risingFast] {
            #expect(!GlucoseAlertCoordinator.breached(type: type, latestMgDL: 40, thresholdMgDL: 3))
            #expect(!GlucoseAlertCoordinator.breached(type: type, latestMgDL: 400, thresholdMgDL: 3))
            #expect(!GlucoseAlertCoordinator.shouldRetract(type: type, latestMgDL: 400, thresholdMgDL: 3))
        }
    }
}

/// Guards the #1428 invariant: "Use CGM App Alerts" suppression applies to
/// reading-driven alarms only. A CGM app can alarm on the current reading,
/// but it cannot compute Trio's oref forecast or carbsReq, so those alarms
/// must stay armed — which is also what the settings screen shows the user,
/// since only reading-driven types move into the "Handled by CGM App" section.
@Suite("Trio Alerts: CGM-ownership suppression scope") struct CGMOwnershipSuppressionScopeTests {
    @Test("Forecast and carbs-required alarms are not reading-driven") func determinationDrivenTypes() {
        #expect(!GlucoseAlertType.forecastedLow.isReadingDriven)
        #expect(!GlucoseAlertType.carbsRequired.isReadingDriven)
    }

    @Test("Only high/low/urgentLow/fallingFast/risingFast are reading-driven") func readingDrivenSetIsExact() {
        let readingDriven = Set(GlucoseAlertType.allCases.filter(\.isReadingDriven))
        #expect(readingDriven == [.high, .low, .urgentLow, .fallingFast, .risingFast])
    }

    @Test("CGM-owned retraction keeps determination-driven alarms firing") func retractsOnlyReadingDrivenAlarms() {
        let urgentLow = GlucoseAlert(type: .urgentLow)
        let low = GlucoseAlert(type: .low)
        let forecastedLow = GlucoseAlert(type: .forecastedLow)
        let high = GlucoseAlert(type: .high)
        let carbsRequired = GlucoseAlert(type: .carbsRequired)
        let alarms = [urgentLow, low, forecastedLow, high, carbsRequired]
        let firing = Set(alarms.map(\.id))

        let result = GlucoseAlertCoordinator.alarmsToRetractWhenCGMOwnsAlerts(firing: firing, in: alarms)

        #expect(result.map(\.id) == [urgentLow.id, low.id, high.id])
        #expect(!result.contains(forecastedLow))
        #expect(!result.contains(carbsRequired))
    }

    @Test("CGM-owned retraction skips reading-driven alarms that are not firing") func skipsNonFiringReadingDrivenAlarms() {
        let low = GlucoseAlert(type: .low)
        let high = GlucoseAlert(type: .high)

        let result = GlucoseAlertCoordinator.alarmsToRetractWhenCGMOwnsAlerts(firing: [high.id], in: [low, high])

        #expect(result == [high])
    }

    @Test("CGM-owned retraction with empty firing set returns nothing") func emptyFiringSetReturnsNothing() {
        let alarms = [GlucoseAlert(type: .urgentLow), GlucoseAlert(type: .low), GlucoseAlert(type: .high)]

        let result = GlucoseAlertCoordinator.alarmsToRetractWhenCGMOwnsAlerts(firing: [], in: alarms)

        #expect(result.isEmpty)
    }
}
