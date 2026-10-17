import Foundation
import Testing
@testable import Trio_Watch_App

/// Phone and watch sides of the glucose history sync, without WatchConnectivity: the phone's payloads are built
/// with the same helpers `BaseWatchManager` uses.
@Suite("Watch glucose history sync") struct WatchGlucoseSyncTests {
    /// Not on a bucket boundary, with fractions like real timestamps.
    static let now: TimeInterval = 1_790_000_123.456
    static let signature = "mg/dL|staticColor|70|180|"

    /// The phone's glucose window, as `setupWatchState` fetches it.
    struct Phone {
        var windowStart: TimeInterval = WatchGlucoseSyncTests.now - 24 * 3600
        var signature = WatchGlucoseSyncTests.signature
        var readings: [[String: Any]] = []

        /// Every 5 minutes up to `until`, oldest first.
        init(until end: TimeInterval = WatchGlucoseSyncTests.now) {
            var timestamp = end
            while timestamp >= windowStart {
                readings.insert(Self.reading(timestamp), at: 0)
                timestamp -= 300
            }
        }

        static func reading(_ timestamp: TimeInterval, glucose: Double? = nil) -> [String: Any] {
            [
                WatchGlucoseSync.readingTimestampKey: timestamp,
                WatchGlucoseSync.readingGlucoseKey: glucose ?? Double(Int(timestamp) % 180 + 60),
                WatchGlucoseSync.readingColorKey: "#00FF00"
            ]
        }

        static func timestamp(of reading: [String: Any]) -> TimeInterval {
            reading[WatchGlucoseSync.readingTimestampKey] as! TimeInterval
        }

        var timestamps: [TimeInterval] { readings.map(Self.timestamp(of:)) }

        mutating func add(at timestamp: TimeInterval, glucose: Double? = nil) {
            readings.append(Self.reading(timestamp, glucose: glucose))
            readings.sort { Self.timestamp(of: $0) < Self.timestamp(of: $1) }
        }

        mutating func removeBucket(_ bucket: Int) {
            readings.removeAll { WatchGlucoseSync.bucket(of: Self.timestamp(of: $0)) == bucket }
        }

        mutating func advance(to end: TimeInterval) {
            var timestamp = timestamps.last! + 300
            while timestamp <= end {
                add(at: timestamp)
                timestamp += 300
            }
            windowStart = end - 24 * 3600
            readings.removeAll { Self.timestamp(of: $0) < windowStart }
        }

        var full: [String: Any] {
            var payload: [String: Any] = [:]
            WatchGlucoseSync.annotateFullHistory(
                &payload,
                readings: readings,
                windowStart: windowStart,
                signature: signature
            )
            return payload
        }

        func delta(since base: TimeInterval) -> [String: Any] {
            WatchGlucoseSync.delta(of: full, since: base)
        }

        func repair(for watch: WatchGlucoseHistory) -> [String: Any] {
            let buckets = watch.bucketChecksumList!
            return WatchGlucoseSync.repair(of: full, watchBucketStart: buckets.start, watchChecksums: buckets.checksums)
        }
    }

    static func synced(with phone: Phone) -> WatchGlucoseHistory {
        var watch = WatchGlucoseHistory()
        #expect(watch.merge(phone.full) == .updated)
        return watch
    }

    static func readingCount(_ payload: [String: Any]) -> Int {
        (payload[WatchMessageKeys.glucoseValues] as? [Any])?.count ?? -1
    }

    static func expectMatches(_ watch: WatchGlucoseHistory, _ phone: Phone) {
        #expect(watch.readings.map(\.timestamp) == phone.timestamps)
    }

    // MARK: - Full history

    @Test("A full history replaces the watch's copy and verifies") func fullHistory() {
        let phone = Phone()
        let watch = Self.synced(with: phone)
        Self.expectMatches(watch, phone)
        #expect(watch.signature == Self.signature)
    }

    @Test("A full history that fails its own checksum is kept but reported unverified") func fullHistoryUnverified() {
        var payload = Phone().full
        payload[WatchMessageKeys.glucoseChecksum] = Int64(42)
        var watch = WatchGlucoseHistory()
        #expect(watch.merge(payload) == .updatedUnverified)
        #expect(!watch.readings.isEmpty)
    }

    @Test("A payload without count and checksum never verifies") func missingChecksum() {
        var payload = Phone().full
        payload.removeValue(forKey: WatchMessageKeys.glucoseChecksum)
        var watch = WatchGlucoseHistory()
        #expect(watch.merge(payload) == .updatedUnverified)
    }

    @Test("A payload without glucose leaves the history alone") func noGlucose() {
        var watch = Self.synced(with: Phone())
        #expect(watch.merge([WatchMessageKeys.iob: "1.2"]) == .unchanged)
    }

    // MARK: - Deltas

    @Test("A delta with the next reading appends it") func deltaAppends() {
        var phone = Phone()
        var watch = Self.synced(with: phone)
        let base = phone.timestamps.last!
        phone.advance(to: base + 300)

        let delta = phone.delta(since: base)
        #expect(Self.readingCount(delta) == 1)
        #expect(watch.merge(delta) == .updated)
        Self.expectMatches(watch, phone)
    }

    @Test("A new reading with the same value as the last one is still a change") func sameValueNewReading() {
        var phone = Phone()
        var watch = Self.synced(with: phone)
        let last = phone.readings.last!
        let base = Phone.timestamp(of: last)
        phone.add(at: base + 300, glucose: last[WatchGlucoseSync.readingGlucoseKey] as? Double)

        #expect(watch.merge(phone.delta(since: base)) == .updated)
        #expect(watch.readings.count == phone.readings.count)
    }

    @Test("A delta overlapping readings the watch has does not duplicate them") func deltaOverlap() {
        var phone = Phone()
        var watch = Self.synced(with: phone)
        let base = phone.timestamps.last!
        phone.advance(to: base + 600)

        // Built on an older base, like a context that arrives after the message.
        #expect(watch.merge(phone.delta(since: base - 3600)) == .updated)
        Self.expectMatches(watch, phone)
    }

    @Test("The context's 2 h tail closes a gap shorter than 2 h") func tailClosesShortGap() {
        var phone = Phone()
        var watch = Self.synced(with: phone)
        phone.advance(to: Self.now + 3600)

        let tail = WatchGlucoseSync.recentTail(of: phone.full, after: Self.now + 3600 - 2 * 3600)!
        #expect(watch.merge(tail) == .updated)
        Self.expectMatches(watch, phone)
    }

    @Test("A delta without local history asks for the full history") func deltaWithoutHistory() {
        let phone = Phone()
        var watch = WatchGlucoseHistory()
        #expect(watch.merge(phone.delta(since: Self.now - 3600)) == .needsFullHistory(reason: "no local history"))
    }

    @Test("A delta with other units or colors asks for the full history") func deltaSignatureChanged() {
        var phone = Phone()
        var watch = Self.synced(with: phone)
        phone.signature = "mmol/L|staticColor|3.9|10|"

        let result = watch.merge(phone.delta(since: phone.timestamps.last!))
        #expect(result == .needsFullHistory(reason: "glucose settings changed"))
        #expect(watch.signature == Self.signature)
    }

    @Test("Readings older than the phone's window start are trimmed") func trimsToPhoneWindow() {
        var phone = Phone()
        var watch = Self.synced(with: phone)
        let base = phone.timestamps.last!
        phone.advance(to: base + 3 * 300)

        #expect(watch.merge(phone.delta(since: base)) == .updated)
        #expect(watch.readings.first!.timestamp >= phone.windowStart)
        Self.expectMatches(watch, phone)
    }

    // MARK: - Mismatches that need a repair

    @Test("A deleted reading fails the delta check and is repaired with one bucket") func deletedReading() {
        var phone = Phone()
        var watch = Self.synced(with: phone)
        let deleted = Phone.timestamp(of: phone.readings.remove(at: 100))
        let base = phone.timestamps.last!
        phone.advance(to: base + 300)

        #expect(watch.merge(phone.delta(since: base)) == .mismatch)

        let repair = phone.repair(for: watch)
        #expect(repair[WatchMessageKeys.glucoseBuckets] as? [Int] == [WatchGlucoseSync.bucket(of: deleted)])
        #expect(Self.readingCount(repair) == 5)
        #expect(watch.merge(repair) == .updated)
        Self.expectMatches(watch, phone)
    }

    @Test("Deleting a bucket's only reading clears that bucket on the watch") func emptiedBucket() {
        var phone = Phone()
        let bucket = WatchGlucoseSync.bucket(of: phone.timestamps[100])
        phone.removeBucket(bucket)
        phone.add(at: Double(bucket) * WatchGlucoseSync.bucketLength + 1)
        var watch = Self.synced(with: phone)
        phone.removeBucket(bucket)

        #expect(watch.merge(phone.delta(since: phone.timestamps.last!)) == .mismatch)

        let repair = phone.repair(for: watch)
        #expect(repair[WatchMessageKeys.glucoseBuckets] as? [Int] == [bucket])
        #expect(Self.readingCount(repair) == 0)
        #expect(watch.merge(repair) == .updated)
        #expect(!watch.readings.contains { WatchGlucoseSync.bucket(of: $0.timestamp) == bucket })
    }

    @Test("A backfilled older reading is repaired with its bucket only") func backfilledReading() {
        var phone = Phone()
        var watch = Self.synced(with: phone)
        let backfilled = phone.timestamps[50] + 150
        phone.add(at: backfilled)

        #expect(watch.merge(phone.delta(since: phone.timestamps.last!)) == .mismatch)

        let repair = phone.repair(for: watch)
        #expect(repair[WatchMessageKeys.glucoseBuckets] as? [Int] == [WatchGlucoseSync.bucket(of: backfilled)])
        #expect(watch.merge(repair) == .updated)
        Self.expectMatches(watch, phone)
    }

    @Test("A changed value with the same count is caught by the checksum") func changedValue() {
        var phone = Phone()
        var watch = Self.synced(with: phone)
        phone.readings[80][WatchGlucoseSync.readingGlucoseKey] = 999.0

        #expect(watch.merge(phone.delta(since: phone.timestamps.last!)) == .mismatch)
        #expect(watch.readings.count == phone.readings.count)

        let repair = phone.repair(for: watch)
        #expect((repair[WatchMessageKeys.glucoseBuckets] as? [Int])?.count == 1)
        #expect(watch.merge(repair) == .updated)
        #expect(watch.readings[80].glucose == 999)
    }

    @Test("After 5 h away, the 2 h tail leaves a gap that the repair fills exactly") func gapAfterTail() {
        var phone = Phone()
        var watch = Self.synced(with: phone)
        let later = Self.now + 5 * 3600
        phone.advance(to: later)

        // The context: only the newest 2 h. Kept and shown, but it can't verify.
        let tail = WatchGlucoseSync.recentTail(of: phone.full, after: later - 2 * 3600)!
        #expect(watch.merge(tail) == .mismatch)
        #expect(watch.newestTimestamp == phone.timestamps.last)

        let repair = phone.repair(for: watch)
        let buckets = repair[WatchMessageKeys.glucoseBuckets] as! [Int]
        let gap = (WatchGlucoseSync.bucket(of: Self.now) ... WatchGlucoseSync.bucket(of: later - 2 * 3600))
        #expect(buckets.allSatisfy { gap.contains($0) || $0 == WatchGlucoseSync.bucket(of: phone.windowStart) })
        #expect(Self.readingCount(repair) < Self.readingCount(phone.full) / 4)
        #expect(watch.merge(repair) == .updated)
        Self.expectMatches(watch, phone)
    }

    @Test("A reading that arrives on the phone after the watch's request is in the repair") func readingDuringRepair() {
        var phone = Phone()
        var watch = Self.synced(with: phone)
        phone.readings.remove(at: 200)
        #expect(watch.merge(phone.delta(since: phone.timestamps.last!)) == .mismatch)

        let buckets = watch.bucketChecksumList!
        phone.advance(to: phone.timestamps.last! + 300)
        let repair = WatchGlucoseSync.repair(of: phone.full, watchBucketStart: buckets.start, watchChecksums: buckets.checksums)

        #expect(watch.merge(repair) == .updated)
        Self.expectMatches(watch, phone)
    }

    @Test("A repair built with other units or colors asks for the full history") func repairSignatureChanged() {
        var phone = Phone()
        var watch = Self.synced(with: phone)
        phone.readings.remove(at: 10)
        #expect(watch.merge(phone.delta(since: phone.timestamps.last!)) == .mismatch)

        phone.signature = "mmol/L|staticColor|3.9|10|"
        #expect(watch.merge(phone.repair(for: watch)) == .needsFullHistory(reason: "glucose settings changed"))
    }

    // MARK: - Phone side of the repair

    @Test("Matching buckets give an empty repair that still verifies") func repairNothingToDo() {
        let phone = Phone()
        var watch = Self.synced(with: phone)

        let repair = phone.repair(for: watch)
        #expect(repair[WatchMessageKeys.glucoseBuckets] as? [Int] == [])
        #expect(Self.readingCount(repair) == 0)
        #expect(watch.merge(repair) == .updated)
    }

    @Test("When more than half the buckets differ, the phone sends the full history") func repairFallsBackToFull() {
        let phone = Phone()
        // Only the oldest 4 h, as if the watch had been away for 20 h.
        var watch = Self.synced(with: Phone(until: Self.now - 20 * 3600))

        let repair = phone.repair(for: watch)
        #expect(repair[WatchMessageKeys.glucoseBuckets] == nil)
        #expect(repair[WatchMessageKeys.glucoseSyncBase] == nil)
        #expect(Self.readingCount(repair) == phone.readings.count)
        #expect(watch.merge(repair) == .updated)
        Self.expectMatches(watch, phone)
    }

    @Test("Buckets older than the phone's window are ignored; the watch trims them") func repairIgnoresOldBuckets() {
        var phone = Phone()
        var watch = Self.synced(with: phone)
        phone.readings.remove(at: 150)
        // The window moves on, while the watch still holds the readings that have left it.
        phone.advance(to: Self.now + 2 * 3600)

        let buckets = watch.bucketChecksumList!
        let firstBucket = WatchGlucoseSync.bucket(of: phone.windowStart)
        #expect(buckets.start < firstBucket)

        let repair = phone.repair(for: watch)
        #expect((repair[WatchMessageKeys.glucoseBuckets] as! [Int]).allSatisfy { $0 >= firstBucket })
        #expect(watch.merge(repair) == .updated)
        Self.expectMatches(watch, phone)
    }

    // MARK: - Buckets and checksums

    @Test("Buckets are fixed 30-minute slots of absolute time") func bucketAlignment() {
        let start = Double(1_000_000) * WatchGlucoseSync.bucketLength
        #expect(WatchGlucoseSync.bucket(of: start) == 1_000_000)
        #expect(WatchGlucoseSync.bucket(of: start + 1799.999) == 1_000_000)
        #expect(WatchGlucoseSync.bucket(of: start + 1800) == 1_000_001)
        #expect(WatchGlucoseSync.bucket(of: start - 0.001) == 999_999)
    }

    @Test("The bucket list is contiguous, with 0 for empty buckets") func bucketListContiguous() {
        let length = WatchGlucoseSync.bucketLength
        let list = WatchGlucoseSync.bucketChecksumList(of: [
            (timestamp: 10 * length + 5, glucose: 100),
            (timestamp: 13 * length + 5, glucose: 120)
        ])!
        #expect(list.start == 10)
        #expect(list.checksums.count == 4)
        #expect(list.checksums[1] == 0 && list.checksums[2] == 0)
        #expect(list.checksums.allSatisfy { $0 >= 0 && $0 <= Int(UInt32.max) })
        #expect(WatchGlucoseSync.bucketChecksumList(of: []) == nil)
    }

    @Test("The checksum does not depend on reading order") func checksumOrderIndependent() {
        let readings = Phone().readings.map {
            (Phone.timestamp(of: $0), $0[WatchGlucoseSync.readingGlucoseKey] as! Double)
        }
        var forward = WatchGlucoseChecksum()
        var backward = WatchGlucoseChecksum()
        readings.forEach { forward.add(timestamp: $0.0, glucose: $0.1) }
        readings.reversed().forEach { backward.add(timestamp: $0.0, glucose: $0.1) }
        #expect(forward.transportValue == backward.transportValue)
        #expect(forward.count == backward.count)
    }

    @Test("A saved and restored history still matches the phone bit for bit") func persistenceRoundTrip() {
        var phone = Phone()
        let watch = Self.synced(with: phone)
        var restored = WatchGlucoseHistory(data: watch.encoded()!)!
        #expect(restored.readings == watch.readings)
        #expect(restored.signature == watch.signature)

        let base = phone.timestamps.last!
        phone.advance(to: base + 300)
        #expect(restored.merge(phone.delta(since: base)) == .updated)
    }

    @Test("Payloads survive a binary property list round trip, as over WatchConnectivity") func propertyListTransport() throws {
        var phone = Phone()
        var watch = Self.synced(with: phone)
        phone.readings.remove(at: 30)
        #expect(watch.merge(phone.delta(since: phone.timestamps.last!)) == .mismatch)

        let data = try PropertyListSerialization.data(fromPropertyList: phone.repair(for: watch), format: .binary, options: 0)
        let received = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(watch.merge(received) == .updated)
        Self.expectMatches(watch, phone)
    }
}
