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
        guard let sgvs = decoded as? [AnyObject] else {
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

public extension Bundle {
    var appGroupSuiteName: String? {
        object(forInfoDictionaryKey: "AppGroupID") as? String
    }
}
