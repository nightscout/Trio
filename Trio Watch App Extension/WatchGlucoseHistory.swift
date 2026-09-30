import Foundation

/// The watch's copy of the phone's glucose window. Readings are kept exactly as sent, so checksums match.
struct WatchGlucoseHistory {
    struct Reading: Equatable, Codable {
        let timestamp: TimeInterval
        let glucose: Double
        let color: String
    }

    enum MergeResult: Equatable {
        case unchanged
        case updated
        /// A full history that fails its own checksum: deltas can't be trusted.
        case updatedUnverified
        /// Also a delta that doesn't connect: the gap is repaired by bucket.
        case mismatch
        case needsFullHistory(reason: String)
    }

    /// Oldest first.
    private(set) var readings: [Reading] = []
    private(set) var signature: String?

    var newestTimestamp: TimeInterval? { readings.last?.timestamp }

    init() {}

    // MARK: - Persistence

    private struct Stored: Codable {
        let readings: [Reading]
        let signature: String?
    }

    init?(data: Data) {
        guard let stored = try? PropertyListDecoder().decode(Stored.self, from: data) else { return nil }
        readings = stored.readings.sorted { $0.timestamp < $1.timestamp }
        signature = stored.signature
    }

    func encoded() -> Data? {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try? encoder.encode(Stored(readings: readings, signature: signature))
    }

    // MARK: - Merging

    mutating func merge(_ payload: [String: Any]) -> MergeResult {
        guard let encoded = payload[WatchMessageKeys.glucoseValues] as? [[String: Any]] else { return .unchanged }
        let incoming = Self.decode(encoded)
        let payloadSignature = payload[WatchMessageKeys.glucoseSignature] as? String

        let repairedBuckets = payload[WatchMessageKeys.glucoseBuckets] as? [Int]

        guard repairedBuckets != nil || payload[WatchMessageKeys.glucoseSyncBase] != nil else {
            readings = incoming
            signature = payloadSignature
            trim(to: payload)
            return verify(against: payload) ? .updated : .updatedUnverified
        }

        guard let signature = signature, payloadSignature == signature else {
            return .needsFullHistory(reason: "glucose settings changed")
        }

        if let repairedBuckets = repairedBuckets {
            let buckets = Set(repairedBuckets)
            readings.removeAll { buckets.contains(WatchGlucoseSync.bucket(of: $0.timestamp)) }
            readings = (readings + incoming).sorted { $0.timestamp < $1.timestamp }
        } else {
            guard let newest = newestTimestamp else {
                return .needsFullHistory(reason: "no local history")
            }
            // The delta may overlap readings the watch already has, or leave a gap before them.
            readings.append(contentsOf: incoming.filter { $0.timestamp > newest })
        }
        trim(to: payload)
        return verify(against: payload) ? .updated : .mismatch
    }

    var bucketChecksumList: (start: Int, checksums: [Int])? {
        WatchGlucoseSync.bucketChecksumList(of: readings.map { (timestamp: $0.timestamp, glucose: $0.glucose) })
    }

    /// Uses the phone's window start, not the watch's clock, so both sides count the same readings.
    private mutating func trim(to payload: [String: Any]) {
        guard let windowStart = payload[WatchMessageKeys.glucoseWindowStart] as? TimeInterval else { return }
        readings.removeAll { $0.timestamp < windowStart }
    }

    private func verify(against payload: [String: Any]) -> Bool {
        guard let expectedCount = payload[WatchMessageKeys.glucoseCount] as? Int,
              let expectedChecksum = payload[WatchMessageKeys.glucoseChecksum] as? Int64
        else { return false }

        var checksum = WatchGlucoseChecksum()
        for reading in readings {
            checksum.add(timestamp: reading.timestamp, glucose: reading.glucose)
        }
        return checksum.count == expectedCount && checksum.transportValue == expectedChecksum
    }

    private static func decode(_ encoded: [[String: Any]]) -> [Reading] {
        encoded.compactMap { entry -> Reading? in
            guard let timestamp = entry[WatchGlucoseSync.readingTimestampKey] as? TimeInterval,
                  let glucose = entry[WatchGlucoseSync.readingGlucoseKey] as? Double,
                  let color = entry[WatchGlucoseSync.readingColorKey] as? String
            else { return nil }
            return Reading(timestamp: timestamp, glucose: glucose, color: color)
        }
        .sorted { $0.timestamp < $1.timestamp }
    }
}
