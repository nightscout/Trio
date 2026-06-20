import Foundation
import LoopKit

/// Internal slug + severity producer for Trio-emitted alerts (APSManager,
/// notLooping, glucose threshold). Pump/device alarms now flow through
/// `AlertCatalogRegistry` and don't touch this enum.
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
    case carbsRequired
    case other(String)

    /// Whether an inbound alert in this category surfaces *immediately*.
    /// `false` means the category is dwell-suppressed by `APSManager`
    /// (count + time threshold) before it reaches `TrioAlertManager`, and
    /// also dropped at the manager boundary if it leaks through. Today
    /// only `commsTransient` qualifies — connectivity blips usually
    /// recover on their own.
    var shouldFireImmediately: Bool {
        switch self {
        case .algorithmError,
             .batteryEmpty,
             .batteryLow,
             .bolusFailed,
             .carbsRequired,
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
        case .commsTransient:
            return false
        }
    }

    /// Slug used when Trio constructs its own `Alert.Identifier`.
    var alertIdentifier: String {
        switch self {
        case .occlusion: return "occlusion"
        case .reservoirLow: return "reservoirLow"
        case .reservoirEmpty: return "reservoirEmpty"
        case .batteryLow: return "batteryLow"
        case .batteryEmpty: return "batteryEmpty"
        case .hardwareFault: return "hardwareFault"
        case .deliveryUncertain: return "deliveryUncertain"
        case .deviceExpirationReminder: return "deviceExpirationReminder"
        case .deviceExpired: return "deviceExpired"
        case .podShutdownImminent: return "podShutdownImminent"
        case .suspendTimeExpired: return "suspendTimeExpired"
        case .bolusFailed: return "bolusFailed"
        case .manualTempBasalActive: return "manualTempBasalActive"
        case .notLooping: return "notLooping"
        case .sensorFailure: return "sensorFailure"
        case .glucoseUrgentLow: return "glucoseUrgentLow"
        case .glucoseLow: return "glucoseLow"
        case .glucoseForecastedLow: return "glucoseForecastedLow"
        case .glucoseHigh: return "glucoseHigh"
        case .glucoseDataStale: return "glucoseDataStale"
        case .algorithmError: return "algorithmError"
        case .commsTransient: return "commsTransient"
        case .carbsRequired: return "carbsRequired"
        case let .other(id): return id
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
             .reservoirEmpty,
             .sensorFailure:
            return .critical
        case .batteryLow,
             .bolusFailed,
             .carbsRequired,
             .deviceExpired,
             .glucoseDataStale,
             .glucoseForecastedLow,
             .glucoseHigh,
             .glucoseLow,
             .manualTempBasalActive,
             .podShutdownImminent,
             .reservoirLow,
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
    /// Classify a Swift error caught at the `APSManager` boundary so dwell
    /// suppression + alert emission have a stable bucket.
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
