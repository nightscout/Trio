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
    /// Shown after the reading's age: a state that needs nothing done (the grace period).
    var watchSensorNote: String? { get }
    /// While warming up, its end: counted down in place of the minutes.
    var watchWarmupEndsAt: Date? { get }
    /// The sensor itself needs a look: the left watch icon in yellow.
    var watchHasSensorProblem: Bool { get }
    /// The sensor gives no more readings (failed, expired): the icon and its text in red.
    var watchSensorHasEnded: Bool { get }
    /// A wake that is not the sensor's own: its acquisition re-checks itself.
    func recheckAcquisition()
    /// The sensor link came up (true) or went down (false), as this log line of the manager's tells; nil otherwise.
    static func watchLinkIsUp(afterLog message: String) -> Bool?
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
        // searching is for a sensor the watch has never connected to; as Loop's sensor page, a passive note only
        if isSearchingForSensor { return String(localized: "Pairing: keep Trio open, accept the request") }
        switch lifecycleState {
        case .warmup: return String(localized: "Sensor warmup")
        case .failed: return String(localized: "Sensor failed")
        case .expired: return String(localized: "Sensor expired")
        default: return nil
        }
    }

    var watchSensorNote: String? {
        lifecycleState == .gracePeriod ? String(localized: "Grace period") : nil
    }

    var watchSensorHasEnded: Bool {
        lifecycleState == .failed || lifecycleState == .expired
    }

    var watchWarmupEndsAt: Date? {
        lifecycleState == .warmup ? sensorFinishesWarmupAt : nil
    }

    // ponytail: the kit tells its observers of scans only, so its connect and disconnect are read from its log
    // lines; a kit status for the link would replace this.
    static func watchLinkIsUp(afterLog message: String) -> Bool? {
        if message == "Sensor connected" { return true }
        if message.hasPrefix("Sensor disconnected") { return false }
        return nil
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
