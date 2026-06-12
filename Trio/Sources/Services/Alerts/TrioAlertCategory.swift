import Foundation
import LoopKit

enum TrioAlertCategory: Equatable {
    case occlusion
    case reservoirLow
    case reservoirEmpty
    case batteryLow
    case batteryEmpty
    case pumpFault
    case podExpirationReminder
    case podExpired
    case podShutdownImminent
    case suspendTimeExpired
    case bolusFailed
    case manualTempBasalActive
    case glucoseUrgentLow
    case glucoseLow
    case glucoseForecastedLow
    case glucoseHigh
    case glucoseDataStale
    case algorithmError
    case commsTransient
    case other(String)

    var isAlertWorthy: Bool {
        switch self {
        case .batteryEmpty,
             .batteryLow,
             .bolusFailed,
             .glucoseDataStale,
             .glucoseForecastedLow,
             .glucoseHigh,
             .glucoseLow,
             .glucoseUrgentLow,
             .manualTempBasalActive,
             .occlusion,
             .other,
             .podExpirationReminder,
             .podExpired,
             .podShutdownImminent,
             .pumpFault,
             .reservoirEmpty,
             .reservoirLow,
             .suspendTimeExpired:
            return true
        case .algorithmError,
             .commsTransient:
            return false
        }
    }

    var interruptionLevel: Alert.InterruptionLevel {
        switch self {
        case .batteryEmpty,
             .glucoseUrgentLow,
             .occlusion,
             .pumpFault,
             .reservoirEmpty:
            return .critical
        case .batteryLow,
             .bolusFailed,
             .glucoseDataStale,
             .glucoseForecastedLow,
             .glucoseHigh,
             .glucoseLow,
             .manualTempBasalActive,
             .podExpired,
             .podShutdownImminent,
             .reservoirLow,
             .suspendTimeExpired:
            return .timeSensitive
        case .algorithmError,
             .commsTransient,
             .other,
             .podExpirationReminder:
            return .active
        }
    }
}

enum TrioAlertClassifier {
    /// Classify a LoopKit alert identifier coming from a pump or CGM manager.
    /// Returns `.other(identifier)` for anything not recognized — keeps untyped
    /// alerts flowing through but marks them as not-alert-worthy by default.
    ///
    /// Coverage mapping by pump manager:
    ///   - Omni family (OmniBLE / OmniKit / OmnipodKit): `userPodExpiration`,
    ///     `podExpiring`, `podExpireImminent`, `lowReservoir`, `suspendEnded`
    ///     (+ untyped: `suspendInProgress`, `finishSetupReminder`,
    ///     `unexpectedAlert`, `timeOffsetChangeDetected`).
    ///   - DanaKit: `occlusion`, `pumpError`, `lowBattery`, `batteryZeroPercent`,
    ///     `shutdown`, `emptyReservoir`, `remainingInsulinLevel`, `checkShaft`
    ///     (+ untyped: `basalCompare`, `bloodSugarMeasure`, `basalMax`,
    ///     `dailyMax`, `bloodSugarCheckMiss`, `ble5InvalidKeys`, `unknown`).
    ///   - MinimedKit: `lowRLBattery`, `PumpBatteryLow`, `PumpReservoirEmpty`,
    ///     `PumpReservoirLow`.
    ///   - MedtrumKit: bypasses LoopKit `AlertIssuer` and posts to
    ///     `UNUserNotificationCenter` directly — alerts do not reach this
    ///     classifier today. Requires a submodule change to issue
    ///     `delegate?.issueAlert(_:)` instead.
    static func categorize(alertIdentifier: String) -> TrioAlertCategory {
        let id = alertIdentifier.lowercased()
        if id.contains("occlusion") { return .occlusion }
        if id.contains("reservoirempty") || id.contains("emptyreservoir") { return .reservoirEmpty }
        if id.contains("lowreservoir") || id.contains("reservoirlow") || id.contains("remaininginsulin") {
            return .reservoirLow
        }
        if id.contains("batteryempty") || id.contains("batteryzero") { return .batteryEmpty }
        if id.contains("lowbattery") || id.contains("batterylow") || id.contains("rlbattery") { return .batteryLow }
        if id.contains("shutdownimminent") || id.contains("expireimminent") { return .podShutdownImminent }
        if id.contains("podexpired") || id.contains("podexpiring") || id.contains("expired") { return .podExpired }
        if id.contains("expirationreminder") || id.contains("userpodexpiration") { return .podExpirationReminder }
        if id.contains("suspendtimeexpired") || id.contains("suspendended") { return .suspendTimeExpired }
        if id.contains("fault") || id.contains("pumperror") || id.contains("checkshaft") || id == "shutdown" {
            return .pumpFault
        }
        if id.contains("bolusfailed") { return .bolusFailed }
        if id.contains("manualtempbasal") { return .manualTempBasalActive }
        if id.contains("glucose.urgentlow") || id.contains("glucoseurgentlow") { return .glucoseUrgentLow }
        if id.contains("glucose.forecastedlow") || id.contains("glucoseforecastedlow") { return .glucoseForecastedLow }
        if id.contains("glucose.low") || id.contains("glucoselow") { return .glucoseLow }
        if id.contains("glucose.high") || id.contains("glucosehigh") { return .glucoseHigh }
        if id.contains("glucose"), id.contains("stale") { return .glucoseDataStale }
        return .other(alertIdentifier)
    }

    /// Classify a Swift error caught at the `APSManager` boundary — these don't
    /// come with a LoopKit alert identifier so we inspect the type + description.
    static func categorize(error: Error) -> TrioAlertCategory {
        if let apsError = error as? APSError {
            switch apsError {
            case let .pumpError(inner):
                return categorize(pumpError: inner)
            case .invalidPumpState:
                return .pumpFault
            case .glucoseError:
                return .glucoseDataStale
            case .apsError:
                return .algorithmError
            case .manualBasalTemp:
                return .manualTempBasalActive
            }
        }
        return categorize(pumpError: error)
    }

    private static func categorize(pumpError: Error) -> TrioAlertCategory {
        let description = String(describing: pumpError).lowercased()
        if description.contains("occlusion") { return .occlusion }
        if description.contains("reservoirempty") || description.contains("emptyreservoir") { return .reservoirEmpty }
        if description.contains("lowreservoir") { return .reservoirLow }
        if description.contains("fault") { return .pumpFault }
        if description.contains("podexpired") { return .podExpired }
        if description.contains("communication") || description.contains("comms") || description.contains("notconnected")
            || description.contains("noresponse") || description.contains("timeout") || description.contains("rssi")
        {
            return .commsTransient
        }
        if description.contains("bolusfailed") || description.contains("uncertaindelivery") { return .bolusFailed }
        return .other(String(describing: pumpError))
    }
}
