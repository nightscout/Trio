import Foundation

enum WatchMessageKeys {
    // Request/Response Keys
    static let date = "date"
    static let units = "units"
    static let requestWatchUpdate = "requestWatchUpdate"
    static let watchState = "watchState"
    static let acknowledged = "acknowledged"
    static let ackCode = "ackCode"
    static let message = "message"

    // Treatment Keys
    static let bolus = "bolus"
    static let carbs = "carbs"
    static let cancelBolus = "cancelBolus"
    static let bolusCanceled = "bolusCanceled"
    static let bolusProgress = "bolusProgress"
    static let activeBolusAmount = "activeBolusAmount"
    static let deliveredAmount = "deliveredAmount"
    static let bolusProgressTimestamp = "bolusProgressTimestamp"

    // Recommendation Keys
    static let requestBolusRecommendation = "requestBolusRecommendation"
    static let recommendedBolus = "recommendedBolus"

    // Override Keys
    static let cancelOverride = "cancelOverride"
    static let activateOverride = "activateOverride"

    // Temp Target Keys
    static let cancelTempTarget = "cancelTempTarget"
    static let activateTempTarget = "activateTempTarget"

    // Watch State Data Keys
    static let currentGlucose = "currentGlucose"
    static let currentGlucoseColorString = "currentGlucoseColorString"
    static let trend = "trend"
    static let delta = "delta"
    static let iob = "iob"
    static let cob = "cob"
    static let lastLoopTime = "lastLoopTime"
    static let glucoseValues = "glucoseValues"
    static let minYAxisValue = "minYAxisValue"
    static let maxYAxisValue = "maxYAxisValue"
    static let overridePresets = "overridePresets"
    static let tempTargetPresets = "tempTargetPresets"

    // Limits and Settings Keys
    static let maxBolus = "maxBolus"
    static let maxCarbs = "maxCarbs"
    static let maxFat = "maxFat"
    static let maxProtein = "maxProtein"
    static let bolusIncrement = "bolusIncrement"
    static let confirmBolusFaster = "confirmBolusFaster"

    // Notification Actions
    static let snoozeDuration = "snoozeDuration"

    // Forecast
    static let showForecastWatch = "showForecastWatch"
    static let isForecastCone = "isForecastCone"
    static let forecastData = "forecastData"
    static let forecastStartDate = "forecastStartDate"
    static let forecastConeMin = "forecastConeMin"
    static let forecastConeMax = "forecastConeMax"
    static let forecastLines = "forecastLines"

    // Glucose history sync
    /// Only set on deltas: the newest reading the delta builds on.
    static let glucoseSyncBase = "glucoseSyncBase"
    static let glucoseWindowStart = "glucoseWindowStart"
    static let glucoseCount = "glucoseCount"
    static let glucoseChecksum = "glucoseChecksum"
    /// Units and color settings the readings were converted with.
    static let glucoseSignature = "glucoseSignature"
    static let supportsGlucoseDelta = "supportsGlucoseDelta"
    static let glucoseSince = "glucoseSince"
    /// Only on repair requests: the watch's checksum per bucket, starting at `glucoseBucketStart`.
    static let glucoseBucketStart = "glucoseBucketStart"
    static let glucoseBucketChecksums = "glucoseBucketChecksums"
    /// Only on repairs: the buckets whose readings replace the watch's.
    static let glucoseBuckets = "glucoseBuckets"
}

enum WatchGlucoseSync {
    static let readingTimestampKey = "date"
    static let readingGlucoseKey = "glucose"
    static let readingColorKey = "color"

    static func annotateFullHistory(
        _ payload: inout [String: Any],
        readings: [[String: Any]],
        windowStart: TimeInterval?,
        signature: String
    ) {
        var checksum = WatchGlucoseChecksum()
        for reading in readings {
            guard let timestamp = reading[readingTimestampKey] as? TimeInterval,
                  let glucose = reading[readingGlucoseKey] as? Double
            else { continue }
            checksum.add(timestamp: timestamp, glucose: glucose)
        }

        payload[WatchMessageKeys.glucoseValues] = readings
        payload[WatchMessageKeys.glucoseCount] = checksum.count
        payload[WatchMessageKeys.glucoseChecksum] = checksum.transportValue
        payload[WatchMessageKeys.glucoseSignature] = signature
        if let windowStart = windowStart {
            payload[WatchMessageKeys.glucoseWindowStart] = windowStart
        }
    }

    /// Count and checksum keep describing the whole window.
    static func delta(of payload: [String: Any], since base: TimeInterval) -> [String: Any] {
        let readings = payload[WatchMessageKeys.glucoseValues] as? [[String: Any]] ?? []

        var delta = payload
        delta[WatchMessageKeys.glucoseValues] = readings.filter { reading in
            guard let timestamp = reading[readingTimestampKey] as? TimeInterval else { return false }
            return timestamp > base
        }
        delta[WatchMessageKeys.glucoseSyncBase] = base
        return delta
    }

    /// `nil` when no reading is older than `cutoff`.
    static func recentTail(of payload: [String: Any], after cutoff: TimeInterval) -> [String: Any]? {
        let readings = payload[WatchMessageKeys.glucoseValues] as? [[String: Any]] ?? []
        let base = readings
            .compactMap { $0[readingTimestampKey] as? TimeInterval }
            .filter { $0 <= cutoff }
            .max()
        guard let base = base else { return nil }
        return delta(of: payload, since: base)
    }

    static func newestTimestamp(in payload: [String: Any]) -> TimeInterval? {
        let readings = payload[WatchMessageKeys.glucoseValues] as? [[String: Any]] ?? []
        return readings.compactMap { $0[readingTimestampKey] as? TimeInterval }.max()
    }

    // MARK: - Bucket repair

    /// Measured on binary plists for 1- and 5-minute CGMs: 30 minutes keeps a request plus the repaired
    /// readings within 15 % of the smallest possible for both.
    static let bucketLength: TimeInterval = 30 * 60

    static func bucket(of timestamp: TimeInterval) -> Int {
        Int((timestamp / bucketLength).rounded(.down))
    }

    /// 32 bits are enough per bucket: a collision is still caught by the window checksum.
    static func bucketChecksums(of readings: [(timestamp: TimeInterval, glucose: Double)]) -> [Int: Int] {
        var checksums: [Int: WatchGlucoseChecksum] = [:]
        for reading in readings {
            checksums[bucket(of: reading.timestamp), default: WatchGlucoseChecksum()]
                .add(timestamp: reading.timestamp, glucose: reading.glucose)
        }
        return checksums.mapValues { Int(UInt32(truncatingIfNeeded: $0.transportValue)) }
    }

    /// Contiguous from the oldest bucket, 0 for an empty one.
    static func bucketChecksumList(of readings: [(timestamp: TimeInterval, glucose: Double)])
        -> (start: Int, checksums: [Int])?
    {
        let checksums = bucketChecksums(of: readings)
        guard let start = checksums.keys.min(), let end = checksums.keys.max() else { return nil }
        return (start, (start ... end).map { checksums[$0] ?? 0 })
    }

    /// Only the readings of the buckets that differ from the watch's, or the full payload when most of them do.
    static func repair(of payload: [String: Any], watchBucketStart: Int, watchChecksums: [Int]) -> [String: Any] {
        guard let windowStart = payload[WatchMessageKeys.glucoseWindowStart] as? TimeInterval else { return payload }
        let readings = payload[WatchMessageKeys.glucoseValues] as? [[String: Any]] ?? []
        let phone = bucketChecksums(of: readings.compactMap { reading in
            guard let timestamp = reading[readingTimestampKey] as? TimeInterval,
                  let glucose = reading[readingGlucoseKey] as? Double
            else { return nil }
            return (timestamp: timestamp, glucose: glucose)
        })
        let watch = Dictionary(
            uniqueKeysWithValues: watchChecksums.enumerated().map { (watchBucketStart + $0.offset, $0.element) }
        )

        // Older buckets have left the window: the watch trims them itself.
        let firstBucket = bucket(of: windowStart)
        let differing = Set(phone.keys).union(watch.keys)
            .filter { $0 >= firstBucket && phone[$0] ?? 0 != watch[$0] ?? 0 }

        let windowBuckets = (phone.keys.max() ?? firstBucket) - firstBucket + 1
        guard differing.count * 2 <= windowBuckets else { return payload }

        var patch = payload
        patch[WatchMessageKeys.glucoseValues] = readings.filter { reading in
            guard let timestamp = reading[readingTimestampKey] as? TimeInterval else { return false }
            return differing.contains(bucket(of: timestamp))
        }
        patch[WatchMessageKeys.glucoseBuckets] = differing.sorted()
        return patch
    }
}

/// Order-independent checksum over the raw values sent, so phone and watch match bit for bit.
struct WatchGlucoseChecksum {
    private(set) var count = 0
    private var sum: UInt64 = 0

    mutating func add(timestamp: TimeInterval, glucose: Double) {
        count += 1
        sum &+= Self.mix(timestamp.bitPattern ^ Self.mix(glucose.bitPattern))
    }

    /// Property lists only hold signed integers.
    var transportValue: Int64 { Int64(bitPattern: sum) }

    /// SplitMix64 finalizer: spreads every input bit over the whole result.
    private static func mix(_ input: UInt64) -> UInt64 {
        var value = input &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
