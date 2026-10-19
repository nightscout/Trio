import CoreData
import Foundation
import LoopKit
import Testing

@testable import Trio

@Suite(
    "Logging Volume Stress Tests",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["TRIO_STRESS"] == "1")
) struct LoggingVolumeStressTests {
    private typealias Fixtures = LoggingStressFixtures

    private class StubManager: DeviceManager {
        class var pluginIdentifier: String { LoggingStressFixtures.pumpManager }
        var localizedTitle: String { "Stress Pump" }
        var debugDescription: String { "## StubManager\npumpSN: \(LoggingStressFixtures.pumpSerial)" }
        var rawState: RawStateValue { [:] }
        var isOnboarded: Bool { true }

        init() {}
        required init?(rawState _: RawStateValue) {}

        func acknowledgeAlert(alertIdentifier _: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
            completion(nil)
        }

        func getSoundBaseURL() -> URL? { nil }
        func getSounds() -> [Alert.Sound] { [] }
        func initializationComplete(for _: [Pluggable]) {}
    }

    private final class StubCGMManager: StubManager {
        override class var pluginIdentifier: String { LoggingStressFixtures.cgmManager }
        override var localizedTitle: String { "Stress CGM" }
        override var debugDescription: String { "## StubCGMManager\ntransmitterID: \(LoggingStressFixtures.transmitterID)" }
    }

    private actor Stores {
        static let shared = Stores()

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LoggingVolumeStress", isDirectory: true)
        // Whole hour so 6 h slice boundaries of a window ending here are known
        let end = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / 3600).rounded(.down) * 3600)
        private var appLog: AppLogStore?
        private var deviceLog: DeviceLogStore?

        var appLogURL: URL { directory.appendingPathComponent("logs/AppLog.sqlite") }
        var deviceLogURL: URL { directory.appendingPathComponent("logs/DeviceLog.sqlite") }

        var boundaries: [Date] { (1 ... 7).map { end.addingTimeInterval(-Double($0) * LogFileWriter.sliceDuration) } }

        func preparedAppLog() async throws -> AppLogStore {
            if let appLog { return appLog }
            let store = try await LoggingVolumeStressTests.ingestAppLog(into: self)
            appLog = store
            return store
        }

        func preparedDeviceLog() async throws -> DeviceLogStore {
            if let deviceLog { return deviceLog }
            let store = try await LoggingVolumeStressTests.ingestDeviceLog(into: self)
            deviceLog = store
            return store
        }

        func reset() {
            appLog = nil
            deviceLog = nil
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static let clock = ContinuousClock()
    private static let ingestPolicy = LogRetentionPolicy(maxAge: 91 * Fixtures.day, persistsDebug: true, maxRows: 100_000_000)
    private static let mb = 1_048_576.0

    private static func rows(
        _ url: URL,
        entity: String,
        load: (URL) -> NSPersistentContainer?,
        predicate: NSPredicate? = nil
    ) -> (count: Int, oldest: Date?, newest: Date?) {
        guard let container = load(url) else { return (0, nil, nil) }
        defer { Fixtures.unload(container) }
        let context = container.newBackgroundContext()
        return context.performAndWait {
            func edge(ascending: Bool) -> Date? {
                let request = NSFetchRequest<NSDictionary>(entityName: entity)
                request.resultType = .dictionaryResultType
                request.predicate = predicate
                request.propertiesToFetch = ["timestamp"]
                request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: ascending)]
                request.fetchLimit = 1
                return (try? context.fetch(request))?.first?["timestamp"] as? Date
            }
            let request = NSFetchRequest<NSDictionary>(entityName: entity)
            request.predicate = predicate
            return ((try? context.count(for: request)) ?? -1, edge(ascending: true), edge(ascending: false))
        }
    }

    private static func appRows(_ url: URL, _ predicate: NSPredicate? = nil) -> (count: Int, oldest: Date?, newest: Date?) {
        rows(url, entity: "AppLogEntry", load: AppLogStore.loadContainer, predicate: predicate)
    }

    private static func deviceRows(_ url: URL, _ predicate: NSPredicate? = nil) -> (count: Int, oldest: Date?, newest: Date?) {
        rows(url, entity: "Entry", load: Fixtures.loadDeviceLogContainer, predicate: predicate)
    }

    private static func since(_ date: Date, manager: String? = nil) -> NSPredicate {
        guard let manager else { return NSPredicate(format: "timestamp >= %@", date as NSDate) }
        return NSPredicate(format: "timestamp >= %@ AND managerIdentifier == %@", date as NSDate, manager)
    }

    private static func ingestAppLog(into stores: Stores) async throws -> AppLogStore {
        let url = await stores.appLogURL
        let end = await stores.end
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let store = AppLogStore(
            storageURL: url,
            policy: ingestPolicy,
            notificationCenter: Foundation.NotificationCenter(),
            isProtectedDataAvailable: { true }
        )
        await store.flush()

        let sampler = MemorySampler()
        var accepted = 0
        var newest = Date.distantPast
        var elapsed = Duration.zero
        for day in 0 ..< Fixtures.days {
            let records = Fixtures.appRecords(day: day, end: end)
            let start = Self.clock.now
            for chunk in stride(from: 0, to: records.count, by: 2000) {
                records[chunk ..< min(chunk + 2000, records.count)].forEach(store.accept)
                await store.flush()
            }
            elapsed += Self.clock.now - start
            accepted += records.count
            newest = max(newest, records.last?.timestamp ?? newest)
        }
        for (index, date) in await stores.boundaries.enumerated() {
            store.accept(LogRecord(
                timestamp: date,
                level: .info,
                category: "Loop",
                message: "#b-app-\(index + 1) slice boundary",
                file: "Stress.swift",
                function: "boundary()",
                line: 1,
                launchID: LaunchID.current
            ))
        }
        await store.flush()
        let peak = sampler.stop()
        accepted += 7

        let ingested = appRows(url)
        let ingestedSize = Fixtures.storeSize(url)
        Fixtures.report("appLog.ingest", [
            "records": "\(accepted)",
            "perDay": "\(accepted / Fixtures.days)",
            "rowsPerSec": String(format: "%.0f", Double(accepted) / Fixtures.seconds(elapsed)),
            "seconds": String(format: "%.1f", Fixtures.seconds(elapsed)),
            "peakResident": Fixtures.megabytes(peak.resident),
            "peakFootprint": Fixtures.megabytes(peak.footprint),
            "sqlite+wal": Fixtures.megabytes(ingestedSize)
        ])
        #expect(ingested.count == accepted)

        var capped = LogRetentionPolicy.default
        capped.maxAge = ingestPolicy.maxAge
        let capStart = Self.clock.now
        store.apply(capped)
        await store.flush()
        let capDuration = Self.clock.now - capStart
        let afterCap = appRows(url)
        let coveredDays = afterCap.oldest.map { end.timeIntervalSince($0) / Fixtures.day } ?? 0
        Fixtures.report("appLog.rowCap", [
            "maxRows": "\(capped.maxRows)",
            "rows": "\(afterCap.count)",
            "daysCovered": String(format: "%.2f", coveredDays),
            "seconds": String(format: "%.2f", Fixtures.seconds(capDuration)),
            "sqlite+wal": Fixtures.megabytes(Fixtures.storeSize(url))
        ])
        #expect(afterCap.count <= capped.maxRows)
        #expect(afterCap.count > capped.maxRows - 1000)
        #expect(afterCap.newest == newest)
        #expect(coveredDays >= 7)

        let ageStart = Self.clock.now
        store.apply(.default)
        await store.flush()
        let ageDuration = Self.clock.now - ageStart
        let afterAge = appRows(url)
        Fixtures.report("appLog.agePurge", [
            "rows": "\(afterAge.count)",
            "oldestAgeDays": String(format: "%.2f", afterAge.oldest.map { Date().timeIntervalSince($0) / Fixtures.day } ?? 0),
            "seconds": String(format: "%.2f", Fixtures.seconds(ageDuration)),
            "sqlite+wal": Fixtures.megabytes(Fixtures.storeSize(url))
        ])
        #expect(afterAge.count <= LogRetentionPolicy.default.maxRows)
        #expect((afterAge.oldest ?? .distantPast) >= Date().addingTimeInterval(-LogRetentionPolicy.default.maxAge - 60))
        #expect(afterAge.newest == newest)
        return store
    }

    private static func ingestDeviceLog(into stores: Stores) async throws -> DeviceLogStore {
        let url = await stores.deviceLogURL
        let end = await stores.end
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let container = try #require(Fixtures.loadDeviceLogContainer(url))
        let context = container.newBackgroundContext()

        let sampler = MemorySampler()
        var counter: Int64 = 0
        var inserted = 0
        var elapsed = Duration.zero
        for day in 0 ..< Fixtures.days {
            let entries = Fixtures.deviceEntries(day: day, end: end)
            let start = Self.clock.now
            try Fixtures.insert(entries, into: context, counter: &counter)
            elapsed += Self.clock.now - start
            inserted += entries.count
        }
        let markers = await stores.boundaries.enumerated().map { index, date in
            StoredDeviceLogEntry(
                type: .send,
                managerIdentifier: Fixtures.pumpManager,
                deviceIdentifier: Fixtures.pumpDevice,
                message: "#b-dev-\(index + 1) slice boundary",
                timestamp: date
            )
        }
        try Fixtures.insert(markers, into: context, counter: &counter)
        inserted += markers.count
        Fixtures.unload(container)
        let ingestPeak = sampler.stop()
        let ingestedSize = Fixtures.storeSize(url)
        #expect(deviceRows(url).count == inserted)
        Fixtures.report("deviceLog.ingest", [
            "entries": "\(inserted)",
            "perDay": "\(inserted / Fixtures.days)",
            "rowsPerSec": String(format: "%.0f", Double(inserted) / Fixtures.seconds(elapsed)),
            "seconds": String(format: "%.1f", Fixtures.seconds(elapsed)),
            "peakFootprint": Fixtures.megabytes(ingestPeak.footprint),
            "sqlite+wal": Fixtures.megabytes(ingestedSize)
        ])

        let purgeSampler = MemorySampler()
        let purgeStart = Self.clock.now
        let store = DeviceLogStore(storageURL: url, isProtectedDataAvailable: { true })
        _ = await store.entries(in: DateInterval(start: end, duration: 1))
        let purgeDuration = Self.clock.now - purgeStart
        let purgePeak = purgeSampler.stop()
        let remaining = deviceRows(url)
        Fixtures.report("deviceLog.openAndPurge", [
            "rows": "\(remaining.count)",
            "oldestAgeDays": String(format: "%.2f", remaining.oldest.map { Date().timeIntervalSince($0) / Fixtures.day } ?? 0),
            "seconds": String(format: "%.2f", Fixtures.seconds(purgeDuration)),
            "peakFootprint": Fixtures.megabytes(purgePeak.footprint),
            "footprintGrowth": Fixtures.megabytes(purgePeak.footprint - min(purgePeak.footprint, purgeSampler.baselineFootprint)),
            "sqlite+walBefore": Fixtures.megabytes(ingestedSize),
            "sqlite+walAfter": Fixtures.megabytes(Fixtures.storeSize(url))
        ])
        #expect((remaining.oldest ?? .distantPast) >= Date().addingTimeInterval(-LogRetentionPolicy.default.maxAge - 60))
        let retired = deviceRows(url, NSPredicate(format: "managerIdentifier == %@", Fixtures.retiredManager)).count
        #expect(retired == 0)
        return store
    }

    private struct Analysis {
        var counts: [String: Int] = [:]
        var duplicates = 0
        var unsorted = 0
        var leaks: [String] = []
        var falseSecrets = 0
        var markers: [String: Int] = [:]
    }

    private static func analyze(_ text: String) -> Analysis {
        var analysis = Analysis()
        analysis.leaks = Fixtures.planted.filter { text.contains($0) }
        guard let range = text.range(of: "\n== Log ==\n") else { return analysis }
        let formatter = LogFileWriter.timestampFormatter()
        var seen = Set<Substring>()
        var previous: Substring = ""
        var previousDate = Date.distantPast
        for line in text[range.upperBound...].split(separator: "\n") {
            guard line.count > 30, line.first?.isNumber == true else { continue }
            let stamp = line.prefix(29)
            if previous.suffix(5) == stamp.suffix(5) {
                if stamp < previous { analysis.unsorted += 1 }
            } else if let date = formatter.date(from: String(stamp)) {
                if date < previousDate { analysis.unsorted += 1 }
                previousDate = date
            }
            previous = stamp
            if !seen.insert(line).inserted { analysis.duplicates += 1 }
            let rest = line.dropFirst(30)
            let source = rest.prefix { $0 != " " }
            analysis.counts[String(source), default: 0] += 1
            if source == "Pump", rest.contains("<secret-") { analysis.falseSecrets += 1 }
            if let marker = rest.range(of: "#b-") {
                analysis.markers[String(rest[marker.lowerBound...].prefix { $0 != " " }), default: 0] += 1
            }
        }
        return analysis
    }

    private static func zip(_ file: URL) throws -> URL {
        let folder = file.deletingLastPathComponent()
        let archive = folder.deletingLastPathComponent().appendingPathComponent("\(folder.lastPathComponent).zip")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipped in
            do {
                try FileManager.default.copyItem(at: zipped, to: archive)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
        return archive
    }

    private static func makeExport(_ appLog: AppLogStore, _ deviceLog: DeviceLogStore) -> LogExport {
        LogExport(appLog: appLog, deviceLogStore: deviceLog, pump: StubManager(), cgm: StubCGMManager())
    }

    @Test("App log store ingests 90 days and purges to the cap, then to 7 days") func appLogIngest() async throws {
        await Stores.shared.reset()
        _ = try await Stores.shared.preparedAppLog()
    }

    @Test("Device log store ingests 90 days and purges to 7 days on open") func deviceLogIngest() async throws {
        _ = try await Stores.shared.preparedDeviceLog()
    }

    @Test("Device log live writes save one entry at a time") func deviceLogLiveWrites() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeviceLogStore(
            storageURL: directory.appendingPathComponent("logs/DeviceLog.sqlite"),
            isProtectedDataAvailable: { true }
        )
        _ = await store.entries(in: DateInterval(start: Date(), duration: 1))
        let count = 5000
        let start = Self.clock.now
        var calls = Duration.zero
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let callStart = Self.clock.now
            defer { calls = Self.clock.now - callStart }
            for index in 0 ..< count {
                store.log(
                    managerIdentifier: Fixtures.pumpManager,
                    deviceIdentifier: Fixtures.pumpDevice,
                    type: .send,
                    message: "#live-dev-\(index) Sending data - OpCode: 1"
                ) { _ in
                    if index == count - 1 { continuation.resume() }
                }
            }
        }
        let duration = Self.clock.now - start
        Fixtures.report("deviceLog.liveLog", [
            "entries": "\(count)",
            "entriesPerSec": String(format: "%.0f", Double(count) / Fixtures.seconds(duration)),
            "secondsUntilPersisted": String(format: "%.2f", Fixtures.seconds(duration)),
            "dayOfDanaSeconds": String(format: "%.1f", 20000 / (Double(count) / Fixtures.seconds(duration))),
            "callSeconds": String(format: "%.2f", Fixtures.seconds(calls))
        ])
        #expect(await store.entries(in: DateInterval(start: Date().addingTimeInterval(-600), end: Date())).count == count)
    }

    @Test("Exports of every kind and length are sorted, complete and redacted") func exports() async throws {
        let appLog = try await Stores.shared.preparedAppLog()
        let deviceLog = try await Stores.shared.preparedDeviceLog()
        let appURL = await Stores.shared.appLogURL
        let deviceURL = await Stores.shared.deviceLogURL
        let export = Self.makeExport(appLog, deviceLog)

        for days in [1, 3, 7] {
            for kind in [LogExport.Kind.all, .pump, .cgm] {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )
                defer { try? FileManager.default.removeItem(at: directory) }
                let span = Double(days) * Fixtures.day
                let before = Date()
                let sampler = MemorySampler()
                let start = Self.clock.now
                let url = try await export.writeLog(kind, days: days, into: directory.appendingPathComponent("log"))
                let duration = Self.clock.now - start
                let peak = sampler.stop()
                let after = Date()
                let zipStart = Self.clock.now
                let archive = try Self.zip(url)
                let zipDuration = Self.clock.now - zipStart
                let textSize = Fixtures.fileSize(url)
                let zipSize = Fixtures.fileSize(archive)
                let analysis = Self.analyze(try String(contentsOf: url, encoding: .utf8))
                let name = "\(kind)-\(days)d"

                Fixtures.report("export.\(name)", [
                    "seconds": String(format: "%.2f", Fixtures.seconds(duration)),
                    "zipSeconds": String(format: "%.2f", Fixtures.seconds(zipDuration)),
                    "peakFootprint": Fixtures.megabytes(peak.footprint),
                    "footprintGrowth": Fixtures.megabytes(peak.footprint - min(peak.footprint, sampler.baselineFootprint)),
                    "txt": Fixtures.megabytes(textSize),
                    "zip": Fixtures.megabytes(zipSize),
                    "ratio": String(format: "%.1f", Double(textSize) / Double(max(zipSize, 1))),
                    "lines": "\(analysis.counts.values.reduce(0, +))",
                    "sources": analysis.counts.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","),
                    "pumpPacketsRedactedAsSecret": "\(analysis.falseSecrets)"
                ])

                #expect(analysis.leaks.isEmpty, "\(name) leaks \(analysis.leaks)")
                #expect(analysis.unsorted == 0, "\(name)")
                #expect(analysis.duplicates == 0, "\(name)")
                #expect(analysis.markers.values.allSatisfy { $0 == 1 }, "\(name) markers \(analysis.markers)")
                #expect(analysis.counts[Fixtures.retiredManager] == nil, "\(name)")

                func expectCount(_ source: String, rows: (Date) -> Int) {
                    let upper = rows(before.addingTimeInterval(-span))
                    let lower = rows(after.addingTimeInterval(-span))
                    let found = analysis.counts[source] ?? 0
                    #expect(found >= lower && found <= upper, "\(name) \(source): \(found) not in \(lower)...\(upper)")
                }
                let expected: Set<String>
                switch kind {
                case .all: expected = ["Trio", "Pump", "CGM"]
                case .pump: expected = ["Pump"]
                case .cgm: expected = ["CGM"]
                }
                #expect(Set(analysis.counts.keys) == expected, "\(name)")
                if expected.contains("Trio") {
                    expectCount("Trio") { Self.appRows(appURL, Self.since($0)).count }
                }
                if expected.contains("Pump") {
                    expectCount("Pump") { Self.deviceRows(deviceURL, Self.since($0, manager: Fixtures.pumpManager)).count }
                }
                if expected.contains("CGM") {
                    expectCount("CGM") { Self.deviceRows(deviceURL, Self.since($0, manager: Fixtures.cgmManager)).count }
                }
                if kind == .all, days == 7 {
                    #expect(Fixtures.seconds(duration) < 60)
                }
            }
        }

        let identifierStart = Self.clock.now
        let window = DateInterval(start: Date().addingTimeInterval(-7 * Fixtures.day), end: Date())
        var identifierEntries = 0
        for slice in LogFileWriter.slices(of: window) {
            identifierEntries += await deviceLog.entries(in: slice).count
        }
        Fixtures.report("export.identifierPass7d", [
            "entries": "\(identifierEntries)",
            "seconds": String(format: "%.2f", Fixtures.seconds(Self.clock.now - identifierStart))
        ])

        let start = Self.clock.now
        let archive = try await export.makeFile(.all, days: 7)
        defer { LogExport.discard(archive) }
        Fixtures.report("export.makeFile-all-7d", [
            "seconds": String(format: "%.2f", Fixtures.seconds(Self.clock.now - start)),
            "zip": Fixtures.megabytes(Fixtures.fileSize(archive))
        ])
    }

    @Test("Slices meet exactly at 6 hour boundaries on real stores") func sliceBoundaries() async throws {
        let appLog = try await Stores.shared.preparedAppLog()
        let deviceLog = try await Stores.shared.preparedDeviceLog()
        let end = await Stores.shared.end
        let window = DateInterval(start: end.addingTimeInterval(-2 * Fixtures.day), end: end)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }

        try await LogFileWriter.write(header: "Header\n", window: window, to: url, redactor: Redactor(exactValues: [])) { slice in
            var lines = await appLog.records(in: slice, minimumLevel: .debug).map(LogExport.line)
            lines += await deviceLog.entries(in: slice).map { LogExport.line(for: $0, source: $0.managerIdentifier) }
            return lines
        }

        let analysis = Self.analyze(try String(contentsOf: url, encoding: .utf8))
        let expectedApp = Self.appRows(
            await Stores.shared.appLogURL,
            NSPredicate(format: "timestamp >= %@ AND timestamp <= %@", window.start as NSDate, window.end as NSDate)
        ).count
        let expectedDevice = Self.deviceRows(
            await Stores.shared.deviceLogURL,
            NSPredicate(format: "timestamp >= %@ AND timestamp < %@", window.start as NSDate, window.end as NSDate)
        ).count
        Fixtures.report("sliceBoundaries", [
            "markers": analysis.markers.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","),
            "appLines": "\(analysis.counts["Trio"] ?? 0)/\(expectedApp)",
            "deviceLines": "\(analysis.counts.filter { $0.key != "Trio" }.values.reduce(0, +))/\(expectedDevice)"
        ])
        #expect(analysis.markers.count == 14)
        #expect(analysis.markers.values.allSatisfy { $0 == 1 })
        #expect(analysis.duplicates == 0)
        #expect(analysis.unsorted == 0)
        #expect(analysis.counts["Trio"] == expectedApp)
        #expect(analysis.counts.filter { $0.key != "Trio" }.values.reduce(0, +) == expectedDevice)
    }

    @Test("Redactor throughput on 100 MB of log text") func redactorThroughput() throws {
        let target = 100 * 1_048_576
        let formatter = LogFileWriter.timestampFormatter()
        let end = Date()
        var chunks: [String] = []
        var chunk = ""
        var total = 0
        var day = 0
        while total < target {
            let lines = Fixtures.appRecords(day: day % Fixtures.days, end: end).map(LogExport.line)
                + Fixtures.deviceEntries(day: day % Fixtures.days, end: end).map { LogExport.line(for: $0, source: "Pump") }
            for line in lines.sorted(by: { $0.date < $1.date }) {
                chunk += LogFileWriter.format(line, formatter: formatter)
                if chunk.utf8.count >= 64 * 1024 {
                    total += chunk.utf8.count
                    chunks.append(chunk)
                    chunk = ""
                    if total >= target { break }
                }
            }
            day += 1
        }

        let redactor = Redactor(exactValues: [
            Redactor.ExactValue(value: Fixtures.siteURL, kind: .url),
            Redactor.ExactValue(value: Fixtures.siteHost, kind: .host),
            Redactor.ExactValue(value: Fixtures.pumpDevice, kind: .device),
            Redactor.ExactValue(value: Fixtures.cgmDevice, kind: .device),
            Redactor.ExactValue(value: Fixtures.retiredDevice, kind: .device)
        ])
        let start = Self.clock.now
        var leaked = 0
        for chunk in chunks {
            let redacted = redactor.redact(chunk)
            leaked += Fixtures.planted.filter { redacted.contains($0) }.count
        }
        let seconds = Fixtures.seconds(Self.clock.now - start)
        Fixtures.report("redactor", [
            "input": Fixtures.megabytes(UInt64(total)),
            "chunks": "\(chunks.count)",
            "seconds": String(format: "%.2f", seconds),
            "mbPerSec": String(format: "%.1f", Double(total) / Self.mb / seconds)
        ])
        #expect(leaked == 0)

        // Per-stage cost on a 10 MB sample, with and without non-ASCII text
        let sample = Array(chunks.prefix(160))
        let ascii = sample.map { String(String.UnicodeScalarView($0.unicodeScalars.filter(\.isASCII))) }
        let sampleSize = Double(sample.reduce(0) { $0 + $1.utf8.count }) / Self.mb
        func rate(_ texts: [String], _ redactor: Redactor) -> String {
            let start = Self.clock.now
            texts.forEach { _ = redactor.redact($0) }
            return String(format: "%.1f", sampleSize / Fixtures.seconds(Self.clock.now - start))
        }
        let exactValues = [Redactor.ExactValue(value: Fixtures.pumpDevice, kind: .device)]
        var stages: [String] = [
            "exactOnly:\(rate(sample, Redactor(exactValues: exactValues, patterns: [])))",
            "exactOnlyASCII:\(rate(ascii, Redactor(exactValues: exactValues, patterns: [])))",
            "allPatternsASCII:\(rate(ascii, Redactor(exactValues: [])))"
        ]
        for (index, pattern) in RedactionPatterns.all.enumerated() {
            stages.append("pattern\(index):\(rate(sample, Redactor(exactValues: [], patterns: [pattern])))")
        }
        // Anchoring the email local part at a token start avoids rescanning every word suffix
        let anchoredEmail =
            try NSRegularExpression(pattern: #"(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#)
        var anchored = RedactionPatterns.all
        anchored[1] = RedactionPatterns.Pattern(regex: anchoredEmail, kind: .email, group: 0)
        stages.append("pattern1Anchored:\(rate(sample, Redactor(exactValues: [], patterns: [anchored[1]])))")
        stages.append("allAnchored:\(rate(sample, Redactor(exactValues: exactValues, patterns: anchored)))")
        let sameOutput = sample.prefix(20).allSatisfy {
            Redactor(exactValues: exactValues).redact($0) == Redactor(exactValues: exactValues, patterns: anchored).redact($0)
        }
        Fixtures.report(
            "redactor.stagesMBPerSec",
            ["stages": stages.joined(separator: ","), "anchoredSameOutput": "\(sameOutput)"]
        )
        #expect(sameOutput)
        withKnownIssue("The unanchored email pattern caps redaction near 1 MB/s") {
            #expect(Double(total) / Self.mb / seconds >= 4)
        }
    }

    @Test("A 20-byte BLE packet in hex survives redaction") func blePacketNotSecret() {
        let packet = "Sending data - Name: CMD_7, OpCode: 7, Encoded data: a5a50c01c86e2a4b9d0f3e771122334455665a5a"
        withKnownIssue("Redactor's bare 40-hex secret pattern also matches 20-byte packet dumps") {
            #expect(Redactor(exactValues: []).redact(packet) == packet)
        }
    }

    @Test("Logging stays non-blocking during a 7-day export") func exportWhileLogging() async throws {
        let appLog = try await Stores.shared.preparedAppLog()
        let deviceLog = try await Stores.shared.preparedDeviceLog()
        let appURL = await Stores.shared.appLogURL
        let export = Self.makeExport(appLog, deviceLog)
        let previous = TrioLogger.sink
        TrioLogger.install(appLog)
        defer { TrioLogger.install(previous) }

        let count = 50000
        func logAll(_ tag: String) async -> [UInt64] {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    var timebase = mach_timebase_info_data_t()
                    mach_timebase_info(&timebase)
                    var latencies = [UInt64](repeating: 0, count: count)
                    for index in 0 ..< count {
                        let start = mach_absolute_time()
                        debug(.loop, "#\(tag).\(index) export stress line with some text")
                        latencies[index] = (mach_absolute_time() - start) * UInt64(timebase.numer) / UInt64(timebase.denom)
                        // ~10 000 lines per second, ten times the heaviest real burst
                        if index % 500 == 499 { Thread.sleep(forTimeInterval: 0.05) }
                    }
                    continuation.resume(returning: latencies.sorted())
                }
            }
        }
        func describe(_ latencies: [UInt64]) -> String {
            let p50 = Double(latencies[latencies.count / 2]) / 1000
            let p99 = Double(latencies[latencies.count * 99 / 100]) / 1000
            let max = Double(latencies.last ?? 0) / 1000
            return String(format: "p50=%.1fus p99=%.1fus max=%.1fus", p50, p99, max)
        }

        let baseline = await logAll("live-idle")
        await appLog.flush()

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = Self.clock.now
        async let file = export.writeLog(.all, days: 7, into: directory)
        let loggingStart = Self.clock.now
        let during = await logAll("live-export")
        let loggingDuration = Self.clock.now - loggingStart
        _ = try await file
        let exportDuration = Self.clock.now - start
        await appLog.flush()

        let idleKept = Self.appRows(appURL, NSPredicate(format: "message BEGINSWITH %@", "#live-idle.")).count
        let exportKept = Self.appRows(appURL, NSPredicate(format: "message BEGINSWITH %@", "#live-export.")).count
        Fixtures.report("exportWhileLogging", [
            "exportSeconds": String(format: "%.2f", Fixtures.seconds(exportDuration)),
            "loggingSeconds": String(format: "%.2f", Fixtures.seconds(loggingDuration)),
            "idle": describe(baseline).replacingOccurrences(of: " ", with: ","),
            "duringExport": describe(during).replacingOccurrences(of: " ", with: ","),
            "persistedIdle": "\(idleKept)/\(count)",
            "persistedDuringExport": "\(exportKept)/\(count)"
        ])
        #expect(Double(during[count * 99 / 100]) < 1_000_000)
        #expect(Fixtures.seconds(exportDuration) < 120)
        #expect(idleKept == count)
        #expect(exportKept == count)
    }

    @Test("Algorithm determinations for 90 days in a test Core Data stack") func determinations() async throws {
        let stack = try await CoreDataStack.createForTests()
        let context = stack.newTaskContext()
        let end = Date()
        let sampler = MemorySampler()
        let start = Self.clock.now
        for day in 0 ..< Fixtures.days {
            try Fixtures.insertDeterminations(day: day, end: end, into: context)
        }
        let insertDuration = Self.clock.now - start
        let peak = sampler.stop()

        let window = DateInterval(start: end.addingTimeInterval(-7 * Fixtures.day), end: end)
        let fetchStart = Self.clock.now
        let fetched = try await context.perform {
            let request: NSFetchRequest<OrefDetermination> = OrefDetermination.fetchRequest()
            request.predicate = NSPredicate(
                format: "deliverAt >= %@ AND deliverAt <= %@",
                window.start as NSDate,
                window.end as NSDate
            )
            request.fetchBatchSize = 100
            return try context.fetch(request).compactMap { determination in
                determination.deliverAt.map { _ in "\(determination.reason ?? "") \(determination.glucose?.stringValue ?? "")" }
            }.count
        }
        let fetchDuration = Self.clock.now - fetchStart
        let total = try await context.perform { try context.count(for: OrefDetermination.fetchRequest()) }
        Fixtures.report("determinations", [
            "rows": "\(total)",
            "forecastValuesPerRow": "\(4 * Fixtures.forecastLength)",
            "insertSeconds": String(format: "%.1f", Fixtures.seconds(insertDuration)),
            "peakFootprint": Fixtures.megabytes(peak.footprint),
            "fetch7dSeconds": String(format: "%.3f", Fixtures.seconds(fetchDuration)),
            "fetched7d": "\(fetched)"
        ])
        #expect(total == Fixtures.days * Fixtures.cyclesPerDay)
        #expect(abs(fetched - 7 * Fixtures.cyclesPerDay) <= 1)
    }

    @Test("Clean up stress stores") func cleanUp() async {
        await Stores.shared.reset()
    }
}
