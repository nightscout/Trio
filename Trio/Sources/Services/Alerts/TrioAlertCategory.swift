import Foundation
import LoopKit

/// Coarse-grained classification of an incoming LoopKit `Alert` or a Swift
/// `Error` caught at the `APSManager` boundary. The user never sees these
/// directly — they pick a *severity tier* on the Device Alarms screen, and
/// each category maps to a tier via `PumpAlertCategory.defaultSeverity`.
///
/// Buckets follow the manager-audit taxonomy:
///   - N1 Hardware Fault        → `.hardwareFault`
///   - N2 Delivery Stopped      → `.suspendTimeExpired` / pump-managed
///   - N3 Uncertain Delivery    → `.deliveryUncertain`
///   - N4 Reservoir Empty       → `.reservoirEmpty`
///   - N5 Battery Dead          → `.batteryEmpty`
///   - N6 Device Expired        → `.deviceExpired` (pod / sensor / transmitter)
///   - N7 Sensor / Session Fail → `.sensorFailure`
///   - F1 Insulin Low           → `.reservoirLow`
///   - F2 Battery Low           → `.batteryLow`
///   - F3 Expiration Approaching → `.deviceExpirationReminder`
///   - Bolus failure (confirmed) → `.bolusFailed`
///   - Glucose alarms           → `.glucose*` (owned by `GlucoseAlertCoordinator`)
///   - N8 Connectivity blips    → `.commsTransient` (dwell-suppressed)
///   - Algorithm error          → `.algorithmError` (dwell-suppressed)
///   - Other unclassified       → `.other(String)`
enum TrioAlertCategory: Equatable {
    case occlusion
    case reservoirLow
    case reservoirEmpty
    case batteryLow
    case batteryEmpty
    case hardwareFault
    case deliveryUncertain
    case deviceExpirationReminder
    case deviceExpired
    case podShutdownImminent
    case suspendTimeExpired
    case bolusFailed
    case manualTempBasalActive
    case notLooping
    case sensorFailure
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
             .deliveryUncertain,
             .deviceExpirationReminder,
             .deviceExpired,
             .glucoseDataStale,
             .glucoseForecastedLow,
             .glucoseHigh,
             .glucoseLow,
             .glucoseUrgentLow,
             .hardwareFault,
             .manualTempBasalActive,
             .notLooping,
             .occlusion,
             .other,
             .podShutdownImminent,
             .reservoirEmpty,
             .reservoirLow,
             .sensorFailure,
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
             .deliveryUncertain,
             .glucoseUrgentLow,
             .hardwareFault,
             .notLooping,
             .occlusion,
             .reservoirEmpty:
            return .critical
        case .batteryLow,
             .bolusFailed,
             .deviceExpired,
             .glucoseDataStale,
             .glucoseForecastedLow,
             .glucoseHigh,
             .glucoseLow,
             .manualTempBasalActive,
             .podShutdownImminent,
             .reservoirLow,
             .sensorFailure,
             .suspendTimeExpired:
            return .timeSensitive
        case .algorithmError,
             .commsTransient,
             .deviceExpirationReminder,
             .other:
            return .active
        }
    }
}

enum TrioAlertClassifier {
    /// Classify a LoopKit alert identifier coming from a pump or CGM manager.
    /// Substring-matched on the lowercased identifier. Returns `.other(identifier)`
    /// for anything unrecognized.
    ///
    /// Coverage notes (manager audit):
    ///   - Pumps: OmniBLE / OmniKit / OmnipodKit / DanaKit / MinimedKit /
    ///     MedtrumKit (MedtrumKit bypasses LoopKit `AlertIssuer` today —
    ///     submodule change required to route through this classifier).
    ///   - CGMs: CGMBLEKit (Dexcom G5/G6), G7SensorKit, LibreTransmitter,
    ///     EversenseKit, NightscoutRemoteCGM, dexcom-share-client-swift.
    static func categorize(alertIdentifier: String) -> TrioAlertCategory {
        let id = alertIdentifier.lowercased()

        // Glucose family — owned by GlucoseAlertCoordinator, return early so the
        // pump/device interception in TrioAlertManager doesn't apply tier config.
        if id.contains("glucose.urgentlow") || id.contains("glucoseurgentlow") { return .glucoseUrgentLow }
        if id.contains("glucose.forecastedlow") || id.contains("glucoseforecastedlow") { return .glucoseForecastedLow }
        if id.contains("glucose.low") || id.contains("glucoselow") { return .glucoseLow }
        if id.contains("glucose.high") || id.contains("glucosehigh") { return .glucoseHigh }
        if id.contains("glucose"), id.contains("stale") { return .glucoseDataStale }

        // Hard-fail device states first (most severe wins on substring overlap).
        if id.contains("occlusion") || id.contains("occluded") { return .occlusion }
        if id.contains("reservoirempty") || id.contains("emptyreservoir") || id.contains("nodelivery")
            || id.contains("reservoirempty")
        {
            return .reservoirEmpty
        }
        if id.contains("batteryempty") || id.contains("batteryzero") || id.contains("batterydepleted")
            || id.contains("batteryout") || id.contains("emptybattery")
        {
            return .batteryEmpty
        }

        // Uncertain delivery — N3, must come before generic bolusFailed.
        if id.contains("unacknowledged") || id.contains("uncertaindelivery") || id.contains("uncertain delivery")
            || id.contains("delivery-uncertain") || id.contains("unabletoreachpod") || id.contains("commsrecovery")
        {
            return .deliveryUncertain
        }

        // Hardware fault — N1. Covers pump faults, transmitter critical faults,
        // CGM hardware errors.
        if id.contains("fault") || id.contains("pumperror") || id.contains("checkshaft")
            || id.contains("autooff") || id.contains("auto-off") || id.contains("devicereset")
            || id.contains("reprogram") || id.contains("unexpectedalert") || id.contains("criticalfault")
            || id.contains("vibrationcurrent") || id.contains("batteryerror") || id.contains("transmittererror")
            || id == "shutdown" || id.contains("unknownalarm")
        {
            return .hardwareFault
        }

        // Sensor / session failure — N7 (CGM-side).
        if id.contains("sensorfailed") || id.contains("sensor.failed") || id.contains("sensorstopped")
            || id.contains("sensorerror") || id.contains("invalidsensor") || id.contains("encryptedsensor")
            || id.contains("sensortemperature") || id.contains("sensorlowtemperature")
            || id.contains("readertemperature") || id.contains("sensorretirement") || id.contains("nosensordetected")
            || id.contains("transmitterdisconnected") || id.contains("glucosesuspended")
            || id.contains("sensorconnection")
        {
            return .sensorFailure
        }

        // Device expired — N6 (pod, sensor, transmitter end-of-life).
        if id.contains("podexpired") || id.contains("podexpiring") || id.contains("sensorexpired")
            || id.contains("sensorretired") || id.contains("transmittereol") || id.contains("sensoragedout")
            || id.contains("mspalarm") || id.contains("expiredsensor") || id.contains("sensorgrace")
            || (id.contains("expired") && !id.contains("suspendtimeexpired"))
        {
            return .deviceExpired
        }
        if id.contains("shutdownimminent") || id.contains("expireimminent") { return .podShutdownImminent }
        if id.contains("expirationreminder") || id.contains("userpodexpiration") || id.contains("retiringsoon")
            || id.contains("sensorending") || id.contains("calibrationgrace") || id.contains("gracePeriod".lowercased())
        {
            return .deviceExpirationReminder
        }

        // Low-supply warnings — F1 / F2.
        if id.contains("lowreservoir") || id.contains("reservoirlow") || id.contains("remaininginsulin") {
            return .reservoirLow
        }
        if id.contains("lowbattery") || id.contains("batterylow") || id.contains("rlbattery")
            || id.contains("verylowbattery") || id.contains("batterystatus")
        {
            return .batteryLow
        }

        // Bolus + delivery state.
        if id.contains("bolusfailed") { return .bolusFailed }
        if id.contains("suspendtimeexpired") || id.contains("suspendended") { return .suspendTimeExpired }
        if id.contains("manualtempbasal") { return .manualTempBasalActive }

        // Loop has not run for the expected interval — emitted internally
        // by the not-looping monitor, not by any pump manager.
        if id.contains("notlooping") || id.contains("loop.notactive") { return .notLooping }

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
                return .hardwareFault
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
        if description.contains("uncertaindelivery") || description.contains("unacknowledged")
            || description.contains("bolus may have failed")
        {
            return .deliveryUncertain
        }
        if description.contains("occlusion") || description.contains("occluded") { return .occlusion }
        if description.contains("reservoirempty") || description.contains("emptyreservoir") { return .reservoirEmpty }
        if description.contains("lowreservoir") { return .reservoirLow }
        if description.contains("fault") || description.contains("patchfault") { return .hardwareFault }
        if description.contains("podexpired") || description.contains("sensorexpired") { return .deviceExpired }
        if description.contains("sensorfailed") || description.contains("sensorstopped") { return .sensorFailure }
        if description.contains("communication") || description.contains("comms") || description.contains("notconnected")
            || description.contains("noresponse") || description.contains("timeout") || description.contains("rssi")
        {
            return .commsTransient
        }
        if description.contains("bolusfailed") { return .bolusFailed }
        return .other(String(describing: pumpError))
    }
}
