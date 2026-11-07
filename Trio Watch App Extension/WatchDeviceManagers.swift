import G7SensorKit
import LoopKit

// The CGMs the watch can read itself, built from the phone's exported configuration (as LoopKit/Loop#2545's
// WatchDeviceManagers). The one place the watch names a device kit: a further CGM needs a kit that builds for watchOS
// and implements `DeviceConfigurationSharing`, an entry in `watchCGMManagersByIdentifier` and a `WatchReadableCGM`
// extension below.

/// What the watch shows and does with a CGM it reads itself.
protocol WatchReadableCGM: CGMManager & DeviceConfigurationSharing {
    /// Posted when anything below changes.
    static var statusDidChange: Notification.Name { get }
    /// Shown in place of the minutes under the glucose bubble: why no readings come (a code, a search, warmup).
    var watchSensorStateText: String? { get }
    /// The sensor itself needs a look: the yellow triangle in the glucose bubble.
    var watchHasSensorProblem: Bool { get }
    /// A wake that is not the sensor's own: its acquisition re-checks itself.
    func recheckAcquisition()
}

/// Keyed by each manager's `pluginIdentifier`, which is what its export carries. Stated, as Trio's device catalog
/// does: LoopKit exposes it only per instance.
let watchCGMManagersByIdentifier: [String: any WatchReadableCGM.Type] = [
    "G7CGMManager": G7CGMManager.self
]

/// A CGM manager built from another controller's export and this watch's saved `localState`.
func watchCGMManager(adopting configuration: SharedDeviceConfiguration, localState: [String: Any]?) -> (any WatchReadableCGM)? {
    watchCGMManagersByIdentifier[configuration.managerIdentifier]?.init(adopting: configuration, localState: localState)
}

/// A CGM manager restored from its saved `managerIdentifier` and `state`.
func watchCGMManager(rawValue: [String: Any]) -> (any WatchReadableCGM)? {
    guard let identifier = rawValue["managerIdentifier"] as? String,
          let rawState = rawValue["state"] as? CGMManager.RawStateValue else { return nil }
    return watchCGMManagersByIdentifier[identifier]?.init(rawState: rawState)
}

extension G7CGMManager: WatchReadableCGM {
    var watchSensorStateText: String? {
        if needsCodeForSensor != nil { return String(localized: "Sensor code needed") }
        if isSearchingForSensor { return String(localized: "Searching for sensor") }
        switch lifecycleState {
        case .warmup: return String(localized: "Sensor warmup")
        case .failed: return String(localized: "Sensor failed")
        case .gracePeriod: return String(localized: "Sensor grace period")
        case .expired: return String(localized: "Sensor expired")
        default: return nil
        }
    }

    var watchHasSensorProblem: Bool {
        switch lifecycleState {
        case .expired,
             .failed,
             .gracePeriod,
             .warmup: return true
        default: return false
        }
    }
}

extension DeviceManager {
    /// What the watch saves, as the phone saves a manager: `managerIdentifier` and `state`.
    var watchRawValue: [String: Any] {
        ["managerIdentifier": pluginIdentifier, "state": rawState]
    }
}
