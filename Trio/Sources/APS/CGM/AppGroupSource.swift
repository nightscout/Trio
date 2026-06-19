import Combine
import Foundation
import LoopKit
import LoopKitUI

public extension GlucoseTrend {
    var direction: String {
        switch self {
        case .upUpUp:
            return "DoubleUp"
        case .upUp:
            return "SingleUp"
        case .up:
            return "FortyFiveUp"
        case .flat:
            return "Flat"
        case .down:
            return "FortyFiveDown"
        case .downDown:
            return "SingleDown"
        case .downDownDown:
            return "DoubleDown"
        }
    }
}

struct AppGroupSource: GlucoseSource {
    var cgmManager: CGMManagerUI?
    var glucoseManager: FetchGlucoseManager?
    let from: String
    var cgmType: CGMType

    let cgmDisplayState = CurrentValueSubject<CgmDisplayState?, Never>(nil)
    let cgmProgressHighlight = CurrentValueSubject<LoopKit.DeviceLifecycleProgress?, Never>(nil)

    func fetch(_ heartbeat: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> {
        guard let suiteName = Bundle.main.appGroupSuiteName,
              let sharedDefaults = UserDefaults(suiteName: suiteName)
        else {
            return Just([]).eraseToAnyPublisher()
        }

        return Just(fetchLastBGs(60, sharedDefaults, heartbeat)).eraseToAnyPublisher()
    }

    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> {
        fetch(nil)
    }

    private func fetchLastBGs(_ count: Int, _ sharedDefaults: UserDefaults, _ heartbeat: DispatchTimer?) -> [BloodGlucose] {
        guard let sharedData = sharedDefaults.data(forKey: "latestReadings") else {
            return []
        }

        HeartBeatManager.shared.checkCGMBluetoothTransmitter(sharedUserDefaults: sharedDefaults, heartbeat: heartbeat)
        debug(.deviceManager, "APPGROUP : START FETCH LAST BG ")
        let decoded = try? JSONSerialization.jsonObject(with: sharedData, options: [])

        // Two shapes accepted:
        //   Legacy (xDrip4iOS today): top-level array of reading dicts.
        //   Rich (xDrip4iOS extended for CGM lifecycle):
        //   top-level dict carrying readings under
        //   `recentReadings` plus sibling keys for CGM status, sensor
        //   lifecycle, and transmitter info — see `applyRichState`.
        let sgvs: [AnyObject]
        if let dict = decoded as? [String: Any] {
            applyRichState(dict)
            sgvs = (dict["recentReadings"] as? [AnyObject]) ?? []
        } else if let arr = decoded as? [AnyObject] {
            applyRichState(nil)
            sgvs = arr
        } else {
            return []
        }

        var results: [BloodGlucose] = []

        for sgv in sgvs.prefix(count) {
            guard
                let glucose = sgv["Value"] as? Int,
                let timestamp = sgv["DT"] as? String,
                let date = parseDate(timestamp)
            else { continue }

            var direction: String?

            // Dexcom changed the format of trend in 2021 so we accept both String/Int types
            if let directionString = sgv["direction"] as? String {
                direction = directionString
            } else if let intTrend = sgv["trend"] as? Int {
                direction = GlucoseTrend(rawValue: intTrend)?.direction
            } else if let intTrend = sgv["Trend"] as? Int {
                direction = GlucoseTrend(rawValue: intTrend)?.direction
            } else if let stringTrend = sgv["trend"] as? String, let intTrend = Int(stringTrend) {
                direction = GlucoseTrend(rawValue: intTrend)?.direction
            }

            guard let direction = direction else { continue }

            if let from = sgv["from"] as? String {
                guard from == self.from else { continue }
            }

            results.append(
                BloodGlucose(
                    sgv: glucose,
                    direction: BloodGlucose.Direction(rawValue: direction),
                    date: Decimal(Int(date.timeIntervalSince1970 * 1000)),
                    dateString: date,
                    unfiltered: Decimal(glucose),
                    filtered: nil,
                    noise: nil,
                    glucose: glucose,
                    type: "sgv"
                )
            )
        }
        return results
    }

    /// Reads the rich top-level dict from xDrip4iOS (when present) and
    /// pushes status + lifecycle into the publishers HomeStateModel
    /// subscribes to. Defensive on every key — xdrip ships partial dicts
    /// during warmup / failure / between sensors.
    private func applyRichState(_ payload: [String: Any]?) {
        guard let payload else {
            cgmDisplayState.value = nil
            cgmProgressHighlight.value = nil
            return
        }

        let cgm = payload["cgm"] as? [String: Any]
        cgmDisplayState.value = parseStatus(cgm?["status"] as? [String: Any])
        cgmProgressHighlight.value = parseSensorLifecycle(cgm?["sensor"] as? [String: Any])
    }

    private func parseStatus(_ status: [String: Any]?) -> CgmDisplayState? {
        guard let status,
              let message = status["localizedMessage"] as? String,
              !message.isEmpty
        else { return nil }
        return CgmDisplayState(
            localizedMessage: message,
            status: cgmDisplayStatus(forCode: status["displayState"] as? String ?? status["code"] as? String)
        )
    }

    /// xDrip4iOS sends a free-form code string (e.g. "normal", "warning",
    /// "critical", "warmup", "calibration_needed", "sensor_failed"). We
    /// fold anything unfamiliar into `.warning` so unknown future codes
    /// surface visibly instead of going silent.
    private func cgmDisplayStatus(forCode code: String?) -> CgmDisplayStatus {
        switch code?.lowercased() {
        case nil,
             "normal",
             "ok": return .normal
        case "critical",
             "expired",
             "sensor_failed",
             "session_failed",
             "stopped": return .critical
        default: return .warning
        }
    }

    private func parseSensorLifecycle(_ sensor: [String: Any]?) -> DeviceLifecycleProgress? {
        guard let sensor else { return nil }
        let percent = (sensor["percentComplete"] as? NSNumber)?.doubleValue
        guard let percent else { return nil }
        let progressState = lifecycleProgressState(
            for: sensor["progressState"] as? String,
            isInWarmup: sensor["isInWarmup"] as? Bool ?? false,
            isExpired: sensor["isExpired"] as? Bool ?? false
        )
        return AppGroupLifecycleProgress(
            percentComplete: max(0, min(1, percent)),
            progressState: progressState
        )
    }

    private func lifecycleProgressState(
        for code: String?,
        isInWarmup: Bool,
        isExpired: Bool
    ) -> DeviceLifecycleProgressState {
        if isExpired { return .critical }
        if isInWarmup { return .normalCGM }
        switch code?.lowercased() {
        case "critical": return .critical
        case "warning": return .warning
        default: return .normalCGM
        }
    }

    private func parseDate(_ timestamp: String) -> Date? {
        // timestamp looks like "/Date(1462404576000)/"
        guard let re = try? NSRegularExpression(pattern: "\\((.*)\\)"),
              let match = re.firstMatch(in: timestamp, range: NSMakeRange(0, timestamp.count))
        else {
            return nil
        }

        let matchRange = match.range(at: 1)
        let epoch = Double((timestamp as NSString).substring(with: matchRange))! / 1000
        return Date(timeIntervalSince1970: epoch)
    }

    func sourceInfo() -> [String: Any]? {
        [GlucoseSourceKey.description.rawValue: "Group ID: \(Bundle.main.appGroupSuiteName ?? String(localized: "Not set"))"]
    }
}

private struct AppGroupLifecycleProgress: DeviceLifecycleProgress {
    let percentComplete: Double
    let progressState: DeviceLifecycleProgressState
}

public extension Bundle {
    var appGroupSuiteName: String? {
        object(forInfoDictionaryKey: "AppGroupID") as? String
    }
}
