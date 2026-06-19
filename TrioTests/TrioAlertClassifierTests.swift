import Foundation
import Testing

@testable import Trio

@Suite("Trio Alerts: TrioAlertClassifier — alertIdentifier round-trip") struct TrioAlertClassifierIdentifierTests {
    /// Ground-truth slugs emitted by bundled pump managers. The classifier is
    /// substring-matched and case-insensitive, so the test inputs reproduce the
    /// real source-of-truth casing.

    // MARK: - OmnipodKit (covers Eros + DASH)

    @Test("Omnipod: lowReservoir → reservoirLow") func omnipodLowReservoir() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "lowReservoir") == .reservoirLow)
    }

    @Test("Omnipod: podExpiring is a reminder, not an expiration") func omnipodPodExpiring() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "podExpiring") == .deviceExpirationReminder)
    }

    @Test("Omnipod: userPodExpiration → reminder") func omnipodUserPodExpiration() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "userPodExpiration") == .deviceExpirationReminder)
    }

    @Test("Omnipod: podExpireImminent → shutdown imminent") func omnipodExpireImminent() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "podExpireImminent") == .podShutdownImminent)
    }

    @Test("Omnipod: suspendEnded → suspendTimeExpired") func omnipodSuspendEnded() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "suspendEnded") == .suspendTimeExpired)
    }

    @Test("Omnipod: suspendEnded-repeating → suspendTimeExpired") func omnipodSuspendEndedRepeating() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "suspendEnded-repeating") == .suspendTimeExpired)
    }

    @Test("Omnipod: unexpectedAlert → hardwareFault") func omnipodUnexpectedAlert() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "unexpectedAlert") == .hardwareFault)
    }

    @Test("Omnipod: timeOffsetChangeDetected → other") func omnipodTimeOffset() {
        // Not a clinically actionable category — falls through to .other.
        if case .other = TrioAlertClassifier.categorize(alertIdentifier: "timeOffsetChangeDetected") {
            // ok
        } else {
            Issue.record("Expected .other for timeOffsetChangeDetected")
        }
    }

    @Test("Omnipod: lowRLBattery → batteryLow") func omnipodLowRLBattery() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "lowRLBattery") == .batteryLow)
    }

    @Test("Omnipod: finishSetupReminder → other") func omnipodFinishSetup() {
        if case .other = TrioAlertClassifier.categorize(alertIdentifier: "finishSetupReminder") {
            // ok
        } else {
            Issue.record("Expected .other for finishSetupReminder")
        }
    }

    @Test("Omnipod: suspendInProgress → other") func omnipodSuspendInProgress() {
        if case .other = TrioAlertClassifier.categorize(alertIdentifier: "suspendInProgress") {
            // ok
        } else {
            Issue.record("Expected .other for suspendInProgress")
        }
    }

    // MARK: - DanaKit

    @Test("Dana: batteryZeroPercent → batteryEmpty") func danaBatteryZero() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "batteryZeroPercent") == .batteryEmpty)
    }

    @Test("Dana: pumpError → hardwareFault") func danaPumpError() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "pumpError") == .hardwareFault)
    }

    @Test("Dana: occlusion") func danaOcclusion() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "occlusion") == .occlusion)
    }

    @Test("Dana: lowBattery → batteryLow") func danaLowBattery() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "lowBattery") == .batteryLow)
    }

    @Test("Dana: shutdown → hardwareFault") func danaShutdown() {
        // The classifier matches the exact lowercased "shutdown" to hardwareFault.
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "shutdown") == .hardwareFault)
    }

    @Test("Dana: emptyReservoir → reservoirEmpty") func danaEmptyReservoir() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "emptyReservoir") == .reservoirEmpty)
    }

    @Test("Dana: remainingInsulinLevel → reservoirLow") func danaRemainingInsulin() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "remainingInsulinLevel") == .reservoirLow)
    }

    @Test("Dana: checkShaft → hardwareFault") func danaCheckShaft() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "checkShaft") == .hardwareFault)
    }

    @Test("Dana: ble5InvalidKeys → other") func danaInvalidKeys() {
        if case .other = TrioAlertClassifier.categorize(alertIdentifier: "ble5InvalidKeys") {
            // ok
        } else {
            Issue.record("Expected .other for ble5InvalidKeys")
        }
    }

    // MARK: - MedtrumKit (jbr7rr/MedtrumKit PR #147)

    @Test("Medtrum: patch-expired → reminder (misnamed, fires PRE-expiry via .delayed)") func medtrumPatchExpiredIsReminder() {
        #expect(
            TrioAlertClassifier
                .categorize(alertIdentifier: "com.nightscout.medtrumkit.patch-expired") == .deviceExpirationReminder
        )
    }

    @Test("Medtrum: patch-occlusion → occlusion") func medtrumOcclusion() {
        #expect(
            TrioAlertClassifier
                .categorize(alertIdentifier: "com.nightscout.medtrumkit.patch-occlusion") == .occlusion
        )
    }

    @Test("Medtrum: patch-fault → hardwareFault") func medtrumPatchFault() {
        #expect(
            TrioAlertClassifier
                .categorize(alertIdentifier: "com.nightscout.medtrumkit.patch-fault") == .hardwareFault
        )
    }

    @Test("Medtrum: patch-empty → reservoirEmpty") func medtrumPatchEmpty() {
        #expect(
            TrioAlertClassifier
                .categorize(alertIdentifier: "com.nightscout.medtrumkit.patch-empty") == .reservoirEmpty
        )
    }

    @Test("Medtrum: reservoir-low → reservoirLow") func medtrumReservoirLow() {
        #expect(
            TrioAlertClassifier
                .categorize(alertIdentifier: "com.nightscout.medtrumkit.reservoir-low") == .reservoirLow
        )
    }

    @Test("Medtrum: patch-daily-limit → suspendTimeExpired (auto-suspend on cap)") func medtrumPatchDailyLimit() {
        #expect(
            TrioAlertClassifier
                .categorize(alertIdentifier: "com.nightscout.medtrumkit.patch-daily-limit") == .suspendTimeExpired
        )
    }

    @Test("Medtrum: patch-hourly-limit → suspendTimeExpired") func medtrumPatchHourlyLimit() {
        #expect(
            TrioAlertClassifier
                .categorize(alertIdentifier: "com.nightscout.medtrumkit.patch-hourly-limit") == .suspendTimeExpired
        )
    }

    // MARK: - MinimedKit

    @Test("Minimed: PumpBatteryLow → batteryLow") func minimedBatteryLow() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "PumpBatteryLow") == .batteryLow)
    }

    @Test("Minimed: PumpReservoirEmpty → reservoirEmpty") func minimedReservoirEmpty() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "PumpReservoirEmpty") == .reservoirEmpty)
    }

    @Test("Minimed: PumpReservoirLow → reservoirLow") func minimedReservoirLow() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "PumpReservoirLow") == .reservoirLow)
    }

    // MARK: - Trio internal slugs (APSManager + NotLoopingMonitor + GlucoseAlertCoordinator)

    @Test("Trio: occlusion") func trioOcclusion() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "occlusion") == .occlusion)
    }

    @Test("Trio: reservoirLow") func trioReservoirLow() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "reservoirLow") == .reservoirLow)
    }

    @Test("Trio: reservoirEmpty") func trioReservoirEmpty() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "reservoirEmpty") == .reservoirEmpty)
    }

    @Test("Trio: batteryLow") func trioBatteryLow() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "batteryLow") == .batteryLow)
    }

    @Test("Trio: batteryEmpty") func trioBatteryEmpty() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "batteryEmpty") == .batteryEmpty)
    }

    @Test("Trio: hardwareFault") func trioHardwareFault() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "hardwareFault") == .hardwareFault)
    }

    @Test("Trio: deliveryUncertain") func trioDeliveryUncertain() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "deliveryUncertain") == .deliveryUncertain)
    }

    @Test("Trio: deviceExpirationReminder") func trioReminder() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "deviceExpirationReminder") == .deviceExpirationReminder)
    }

    @Test("Trio: deviceExpired") func trioExpired() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "deviceExpired") == .deviceExpired)
    }

    @Test("Trio: podShutdownImminent") func trioShutdownImminent() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "podShutdownImminent") == .podShutdownImminent)
    }

    @Test("Trio: suspendTimeExpired") func trioSuspendTimeExpired() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "suspendTimeExpired") == .suspendTimeExpired)
    }

    @Test("Trio: bolusFailed") func trioBolusFailed() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "bolusFailed") == .bolusFailed)
    }

    @Test("Trio: manualTempBasalActive") func trioManualTempBasal() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "manualTempBasalActive") == .manualTempBasalActive)
    }

    @Test("Trio: notLooping") func trioNotLooping() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "notLooping") == .notLooping)
    }

    @Test("Trio: loop.notActive (NotLoopingMonitor slug)") func trioLoopNotActive() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "loop.notActive") == .notLooping)
    }

    @Test("Trio: sensorFailure") func trioSensorFailure() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "sensorFailure") == .sensorFailure)
    }

    @Test("Trio: algorithmError") func trioAlgorithmError() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "algorithmError") == .algorithmError)
    }

    @Test("Trio: glucose.urgentLow.<uuid>") func trioGlucoseUrgentLow() {
        #expect(
            TrioAlertClassifier
                .categorize(alertIdentifier: "glucose.urgentLow.5C9C3D2A-1234-4321-9876-ABCDEF012345") == .glucoseUrgentLow
        )
    }

    @Test("Trio: glucose.low.<uuid>") func trioGlucoseLow() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "glucose.low.uuid-1") == .glucoseLow)
    }

    @Test("Trio: glucose.forecastedLow.<uuid>") func trioGlucoseForecastedLow() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "glucose.forecastedLow.uuid-2") == .glucoseForecastedLow)
    }

    @Test("Trio: glucose.high.<uuid>") func trioGlucoseHigh() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "glucose.high.uuid-3") == .glucoseHigh)
    }

    // MARK: - CGM driver slugs the classifier should recognize when bridges land

    @Test("CGM: sensorFailed → sensorFailure") func cgmSensorFailed() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "sensorFailed") == .sensorFailure)
    }

    @Test("CGM: sensorStopped → sensorFailure") func cgmSensorStopped() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "sensorStopped") == .sensorFailure)
    }

    @Test("CGM: transmitterDisconnected → sensorFailure") func cgmTransmitterDisconnected() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "transmitterDisconnected") == .sensorFailure)
    }

    @Test("CGM: sensorExpired → deviceExpired") func cgmSensorExpired() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "sensorExpired") == .deviceExpired)
    }

    @Test("CGM: transmitterEoL → deviceExpired") func cgmTransmitterEoL() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "transmitterEoL") == .deviceExpired)
    }

    @Test("CGM: sensorGrace → reminder, not expired") func cgmSensorGrace() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "sensorGrace") == .deviceExpirationReminder)
    }

    @Test("CGM: gracePeriod → reminder") func cgmGracePeriod() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "gracePeriod") == .deviceExpirationReminder)
    }

    @Test("CGM: transmitterError → hardwareFault") func cgmTransmitterError() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "transmitterError") == .hardwareFault)
    }

    @Test("CGM: criticalFault → hardwareFault") func cgmCriticalFault() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "criticalFault") == .hardwareFault)
    }

    // MARK: - Glucose family wins over substring overlap

    @Test("Glucose stale beats the generic 'glucose' fallthrough") func glucoseDataStale() {
        #expect(TrioAlertClassifier.categorize(alertIdentifier: "glucoseDataStale") == .glucoseDataStale)
    }

    // MARK: - Unrecognized slug

    @Test("Unrecognized slug → .other with original identifier") func unrecognizedFallsThrough() {
        let category = TrioAlertClassifier.categorize(alertIdentifier: "totallyMadeUpSlug")
        if case let .other(id) = category {
            #expect(id == "totallyMadeUpSlug")
        } else {
            Issue.record("Expected .other(\"totallyMadeUpSlug\")")
        }
    }
}

@Suite("Trio Alerts: TrioAlertClassifier — error round-trip") struct TrioAlertClassifierErrorTests {
    @Test("APSError.invalidPumpState → hardwareFault") func invalidPumpState() {
        let err = APSError.invalidPumpState(message: "x")
        #expect(TrioAlertClassifier.categorize(error: err) == .hardwareFault)
    }

    @Test("APSError.glucoseError → glucoseDataStale") func glucoseError() {
        let err = APSError.glucoseError(message: "x")
        #expect(TrioAlertClassifier.categorize(error: err) == .glucoseDataStale)
    }

    @Test("APSError.apsError → algorithmError") func apsErrorCase() {
        let err = APSError.apsError(message: "x")
        #expect(TrioAlertClassifier.categorize(error: err) == .algorithmError)
    }

    @Test("APSError.manualBasalTemp → manualTempBasalActive") func manualBasalTemp() {
        let err = APSError.manualBasalTemp(message: "x")
        #expect(TrioAlertClassifier.categorize(error: err) == .manualTempBasalActive)
    }

    /// `categorize(pumpError:)` keys on `String(describing:)`, not
    /// `localizedDescription`. Match that contract with `CustomStringConvertible`
    /// so the fake errors actually expose the substring the classifier looks for.
    private struct PumpFake: Error, CustomStringConvertible {
        let description: String
    }

    @Test("APSError.pumpError(occlusion) descends into pumpError categorize") func pumpErrorOcclusion() {
        let err = APSError.pumpError(PumpFake(description: "Pump occlusion detected"))
        #expect(TrioAlertClassifier.categorize(error: err) == .occlusion)
    }

    @Test("APSError.pumpError(uncertain) → deliveryUncertain") func pumpErrorUncertain() {
        let err = APSError.pumpError(PumpFake(description: "UncertainDelivery: bolus may have failed"))
        #expect(TrioAlertClassifier.categorize(error: err) == .deliveryUncertain)
    }

    @Test("APSError.pumpError(timeout) → commsTransient") func pumpErrorComms() {
        let err = APSError.pumpError(PumpFake(description: "Communication timeout, no response"))
        #expect(TrioAlertClassifier.categorize(error: err) == .commsTransient)
    }

    @Test("Generic error → .other") func genericError() {
        struct OddError: Error {}
        let category = TrioAlertClassifier.categorize(error: OddError())
        if case .other = category {
            // ok
        } else {
            Issue.record("Expected .other for unrecognized error")
        }
    }
}

@Suite("Trio Alerts: TrioAlertClassifier — surfacing rules") struct TrioAlertCategorySurfacingTests {
    @Test("commsTransient is the only category dwell-gated at both boundaries") func commsTransientNotImmediate() {
        #expect(!TrioAlertCategory.commsTransient.shouldFireImmediately)
        // Spot-check that everything else surfaces immediately.
        let immediate: [TrioAlertCategory] = [
            .occlusion, .reservoirLow, .reservoirEmpty, .batteryLow, .batteryEmpty,
            .hardwareFault, .deliveryUncertain, .deviceExpirationReminder, .deviceExpired,
            .podShutdownImminent, .suspendTimeExpired, .bolusFailed, .manualTempBasalActive,
            .notLooping, .sensorFailure, .glucoseUrgentLow, .glucoseLow, .glucoseForecastedLow,
            .glucoseHigh, .glucoseDataStale, .algorithmError, .other("any")
        ]
        for category in immediate {
            #expect(category.shouldFireImmediately, "Expected \(category) to surface immediately")
        }
    }

    @Test("sensorFailure default tier is Critical") func sensorFailureCritical() {
        #expect(PumpAlertCategory.sensorFailure.defaultSeverity == .critical)
    }

    @Test("algorithmError defaults to Normal") func algorithmErrorNormal() {
        #expect(PumpAlertCategory.algorithmError.defaultSeverity == .normal)
    }

    @Test("Identifier slug round-trips through the classifier for every category") func slugRoundTrip() {
        for category in PumpAlertCategory.allCases {
            // Build the canonical slug from the matching TrioAlertCategory if available.
            let trioCategory = TrioAlertCategory.allCasesForRoundTripTest
                .first(where: { PumpAlertCategory(trioCategory: $0) == category })
            guard let trioCategory else { continue }
            let slug = trioCategory.alertIdentifier
            let reclassified = TrioAlertClassifier.categorize(alertIdentifier: slug)
            #expect(
                reclassified == trioCategory,
                "Slug \"\(slug)\" should reclassify as \(trioCategory) but got \(reclassified)"
            )
        }
    }
}

// Helper: TrioAlertCategory is not CaseIterable because of `.other(String)`,
// so we enumerate the round-trippable cases explicitly for the round-trip test.
extension TrioAlertCategory {
    static var allCasesForRoundTripTest: [TrioAlertCategory] {
        [
            .occlusion, .reservoirLow, .reservoirEmpty, .batteryLow, .batteryEmpty,
            .hardwareFault, .deliveryUncertain, .deviceExpirationReminder, .deviceExpired,
            .podShutdownImminent, .suspendTimeExpired, .bolusFailed, .manualTempBasalActive,
            .notLooping, .sensorFailure, .glucoseUrgentLow, .glucoseLow, .glucoseForecastedLow,
            .glucoseHigh, .glucoseDataStale, .algorithmError, .commsTransient
        ]
    }
}
