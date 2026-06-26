import Foundation
import LoopKit
import Testing

@testable import Trio

/// Pins the severity + immediacy mapping for every `TrioAlertCategory` case.
/// A re-bucketing of any case (or an added/removed case) fails these tables.
@Suite("Trio Alerts: TrioAlertCategory") struct TrioAlertCategoryTests {
    @Test("interruptionLevel maps each category to its severity tier", arguments: [
        // .critical
        (TrioAlertCategory.batteryEmpty, Alert.InterruptionLevel.critical),
        (.deliveryUncertain, .critical),
        (.glucoseUrgentLow, .critical),
        (.hardwareFault, .critical),
        (.notLooping, .critical),
        (.occlusion, .critical),
        (.reservoirEmpty, .critical),
        (.sensorFailure, .critical),
        // .timeSensitive
        (.batteryLow, .timeSensitive),
        (.bolusFailed, .timeSensitive),
        (.carbsRequired, .timeSensitive),
        (.deviceExpired, .timeSensitive),
        (.glucoseDataStale, .timeSensitive),
        (.glucoseForecastedLow, .timeSensitive),
        (.glucoseHigh, .timeSensitive),
        (.glucoseLow, .timeSensitive),
        (.manualTempBasalActive, .timeSensitive),
        (.podShutdownImminent, .timeSensitive),
        (.reservoirLow, .timeSensitive),
        (.suspendTimeExpired, .timeSensitive),
        // .active
        (.algorithmError, .active),
        (.commsTransient, .active),
        (.deviceExpirationReminder, .active),
        (.other("x"), .active)
    ]) func interruptionLevelMapping(category: TrioAlertCategory, expected: Alert.InterruptionLevel) {
        #expect(category.interruptionLevel == expected)
    }

    @Test("shouldFireImmediately is true for every category except commsTransient", arguments: [
        (TrioAlertCategory.algorithmError, true),
        (.batteryEmpty, true),
        (.batteryLow, true),
        (.bolusFailed, true),
        (.carbsRequired, true),
        (.deliveryUncertain, true),
        (.deviceExpirationReminder, true),
        (.deviceExpired, true),
        (.glucoseDataStale, true),
        (.glucoseForecastedLow, true),
        (.glucoseHigh, true),
        (.glucoseLow, true),
        (.glucoseUrgentLow, true),
        (.hardwareFault, true),
        (.manualTempBasalActive, true),
        (.notLooping, true),
        (.occlusion, true),
        (.other("x"), true),
        (.podShutdownImminent, true),
        (.reservoirEmpty, true),
        (.reservoirLow, true),
        (.sensorFailure, true),
        (.suspendTimeExpired, true),
        (.commsTransient, false)
    ]) func shouldFireImmediatelyMapping(category: TrioAlertCategory, expected: Bool) {
        #expect(category.shouldFireImmediately == expected)
    }

    @Test("commsTransient is dwell-suppressed") func commsTransientDoesNotFireImmediately() {
        #expect(TrioAlertCategory.commsTransient.shouldFireImmediately == false)
    }
}
