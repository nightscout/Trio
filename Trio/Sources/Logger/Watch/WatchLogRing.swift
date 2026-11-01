import Foundation
import os

struct WatchLogDraft: Sendable {
    let date: Date
    let level: WatchLogEntry.Level
    let category: WatchLogEntry.Category
    let message: String
}

// Append-only JSONL segments; whole segments are dropped once the ring is over its limits
final class WatchLogRing {
    struct Limits {
        var maxAge: TimeInterval = 2 * 24 * 60 * 60
        var maxEntries = 5000
        var maxBytes = 1_000_000
        var segmentEntries = 500
        var segmentBytes = 100_000
    }

    private struct Segment {
        let url: URL
        let firstSeq: UInt64
        var lastSeq: UInt64
        var count: Int
        var bytes: Int
        var lastDate: Date
        var isOpen: Bool
    }

    private enum Key {
        static let nextSeq = "WatchLogRing.nextSeq"
        static let ackedSeq = "WatchLogRing.ackedSeq"
        static let installID = "WatchLogRing.installID"
    }

    private static let osLog = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "Trio", category: "WatchLog")

    let directory: URL
    let installID: String
    private let defaults: UserDefaults
    private let limits: Limits
    private var segments: [Segment] = []
    private(set) var nextSeq: UInt64
    private(set) var ackedSeq: UInt64

    var lastSeq: UInt64 { nextSeq - 1 }
    var count: Int { segments.reduce(0) { $0 + $1.count } }
    var bytes: Int { segments.reduce(0) { $0 + $1.bytes } }

    static var defaultDirectory: URL {
        (
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default
                .temporaryDirectory
        )
        .appendingPathComponent("WatchLogs", isDirectory: true)
    }

    init(directory: URL = WatchLogRing.defaultDirectory, defaults: UserDefaults = .standard, limits: Limits = Limits()) {
        self.directory = directory
        self.defaults = defaults
        self.limits = limits

        if let stored = defaults.string(forKey: Key.installID) {
            installID = stored
        } else {
            installID = UUID().uuidString
            defaults.set(installID, forKey: Key.installID)
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = directory
            try url.setResourceValues(values)
        } catch {
            Self.osLog.error("Watch log directory setup failed: \(String(describing: error), privacy: .public)")
        }

        nextSeq = max(1, (defaults.object(forKey: Key.nextSeq) as? NSNumber)?.uint64Value ?? 1)
        ackedSeq = (defaults.object(forKey: Key.ackedSeq) as? NSNumber)?.uint64Value ?? 0
        segments = scan()
        if let last = segments.last, last.lastSeq >= nextSeq {
            nextSeq = last.lastSeq + 1
        }
        ackedSeq = min(ackedSeq, lastSeq)
    }

    func append(_ drafts: [WatchLogDraft]) {
        var remaining = drafts[...]
        while !remaining.isEmpty {
            let index = writableSegment(startingAt: nextSeq, date: remaining[remaining.startIndex].date)
            let room = max(1, limits.segmentEntries - segments[index].count)
            let chunk = remaining.prefix(room)
            remaining = remaining.dropFirst(chunk.count)

            let entries = chunk.enumerated().map { offset, draft in
                WatchLogEntry(
                    seq: nextSeq + UInt64(offset),
                    date: draft.date,
                    level: draft.level,
                    category: draft.category,
                    message: draft.message
                )
            }
            let data = WatchLogEntry.jsonLines(entries)
            do {
                let handle = try FileHandle(forWritingTo: segments[index].url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                Self.osLog.error("Watch log append failed: \(String(describing: error), privacy: .public)")
                segments[index].isOpen = false
                continue
            }
            guard let last = entries.last else { continue }
            segments[index].lastSeq = last.seq
            segments[index].count += entries.count
            segments[index].bytes += data.count
            segments[index].lastDate = last.date
            nextSeq = last.seq + 1
        }
        defaults.set(NSNumber(value: nextSeq), forKey: Key.nextSeq)
    }

    func entries(after seq: UInt64) -> [WatchLogEntry] {
        segments.filter { $0.lastSeq >= $0.firstSeq && $0.lastSeq > seq }.flatMap { segment -> [WatchLogEntry] in
            guard let data = try? Data(contentsOf: segment.url) else { return [] }
            return WatchLogEntry.entries(fromJSONLines: data).filter { $0.seq > seq }
        }
    }

    func acknowledge(_ seq: UInt64) {
        let seq = min(seq, lastSeq)
        guard seq > ackedSeq else { return }
        ackedSeq = seq
        defaults.set(NSNumber(value: seq), forKey: Key.ackedSeq)
    }

    func prune(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-limits.maxAge)
        var count = self.count
        var bytes = self.bytes
        while let oldest = segments.first {
            let isLast = segments.count == 1
            let overLimit = !isLast && (count > limits.maxEntries || bytes > limits.maxBytes)
            guard overLimit || oldest.lastDate < cutoff else { break }
            do {
                try FileManager.default.removeItem(at: oldest.url)
            } catch {
                Self.osLog.error("Watch log segment removal failed: \(String(describing: error), privacy: .public)")
            }
            segments.removeFirst()
            count -= oldest.count
            bytes -= oldest.bytes
        }
    }

    private func writableSegment(startingAt seq: UInt64, date: Date) -> Int {
        if let last = segments.indices.last, segments[last].isOpen,
           segments[last].count < limits.segmentEntries,
           segments[last].bytes < limits.segmentBytes
        {
            return last
        }
        let url = directory.appendingPathComponent(String(format: "%020llu.jsonl", seq))
        if !FileManager.default.createFile(atPath: url.path, contents: nil) {
            Self.osLog.error("Watch log segment creation failed")
        }
        segments.append(Segment(url: url, firstSeq: seq, lastSeq: seq - 1, count: 0, bytes: 0, lastDate: date, isOpen: true))
        return segments.count - 1
    }

    private func scan() -> [Segment] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return files.filter { $0.pathExtension == "jsonl" }.compactMap { url -> Segment? in
            guard let firstSeq = UInt64(url.deletingPathExtension().lastPathComponent),
                  let data = try? Data(contentsOf: url)
            else { return nil }
            let entries = WatchLogEntry.entries(fromJSONLines: data)
            guard let last = entries.last else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return Segment(
                url: url,
                firstSeq: firstSeq,
                lastSeq: last.seq,
                count: entries.count,
                bytes: data.count,
                lastDate: last.date,
                // A torn final line would swallow the next append
                isOpen: data.last == 0x0A
            )
        }
        .sorted { $0.firstSeq < $1.firstSeq }
    }
}
