import Foundation
import Testing

@testable import Trio

@Suite("Watch Log Ingest Tests") struct WatchLogIngestTests {
    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName: String
        let defaults: UserDefaults
        let sink: InMemoryLogSink
        let ingest: WatchLogIngest

        init() throws {
            let suiteName = "WatchLogIngestTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            self.suiteName = suiteName
            let sink = InMemoryLogSink()
            self.defaults = defaults
            self.sink = sink
            ingest = WatchLogIngest(defaults: defaults, sink: { sink })
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }

        func received(_ entries: [WatchLogEntry], installID: String = "install-a") throws -> (URL, [String: Any]) {
            let url = directory.appendingPathComponent("\(UUID().uuidString).jsonl")
            try WatchLogEntry.jsonLines(entries).write(to: url)
            return (url, Self.metadata(entries, installID: installID))
        }

        func stage(_ entries: [WatchLogEntry], installID: String = "install-a") throws -> WatchLogIngest.Batch {
            let (url, metadata) = try received(entries, installID: installID)
            return try #require(WatchLogIngest.stage(url, metadata: metadata, into: directory.appendingPathComponent("staged")))
        }

        static func metadata(_ entries: [WatchLogEntry], installID: String) -> [String: Any] {
            [
                WatchLogTransfer.marker: WatchLogTransfer.version,
                WatchLogTransfer.firstSeq: NSNumber(value: entries.first?.seq ?? 1),
                WatchLogTransfer.lastSeq: NSNumber(value: entries.last?.seq ?? 1),
                WatchLogTransfer.watchBuild: "1.0 (1)",
                WatchLogTransfer.installID: installID
            ]
        }
    }

    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static func entries(_ seqs: ClosedRange<UInt64>) -> [WatchLogEntry] {
        seqs.map {
            WatchLogEntry(
                seq: $0,
                date: start.addingTimeInterval(Double($0) / 4),
                level: .info,
                category: .connectivity,
                message: "entry \($0)"
            )
        }
    }

    @Test("Overlapping batches arriving together are stored once") func overlappingBatches() async throws {
        let fixture = try Fixture()
        let batches = try [Self.entries(1 ... 40), Self.entries(1 ... 60), Self.entries(21 ... 80)].map { try fixture.stage($0) }

        let acks = await withTaskGroup(of: UInt64.self) { group in
            for batch in batches {
                group.addTask { await fixture.ingest.ingest(batch) }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        let messages = fixture.sink.snapshot().map(\.message)
        #expect(messages.count == 80)
        #expect(Set(messages).count == 80)
        #expect(acks.max() == 80)
    }

    @Test("Entries survive a JSON lines round trip with millisecond dates") func codecRoundTrip() {
        let entries = WatchLogEntry.Level.allCases.enumerated().map { index, level in
            WatchLogEntry(
                seq: UInt64(index + 1),
                date: Self.start.addingTimeInterval(Double(index) * 0.25),
                level: level,
                category: WatchLogEntry.Category.allCases[index % WatchLogEntry.Category.allCases.count],
                message: "message \(index) with \"quotes\"\nand a newline"
            )
        }
        var data = WatchLogEntry.jsonLines(entries)
        data.append(Data(#"{"seq":99,"le"#.utf8))

        #expect(WatchLogEntry.entries(fromJSONLines: data) == entries)

        let precise = WatchLogEntry(
            seq: 1,
            date: Self.start.addingTimeInterval(0.123),
            level: .debug,
            category: .data,
            message: ""
        )
        let decoded = WatchLogEntry.entries(fromJSONLines: WatchLogEntry.jsonLines([precise])).first
        #expect(abs((decoded?.date.timeIntervalSince(precise.date)) ?? 1) < 0.0005)
    }

    @Test("Ingested entries keep their level, category and date") func mapsRecords() async throws {
        let fixture = try Fixture()
        let levels: [(WatchLogEntry.Level, LogLevel)] = [
            (.debug, .debug), (.info, .info), (.warning, .warning), (.error, .error), (.fault, .fault)
        ]
        let entries = levels.enumerated().map { index, pair in
            WatchLogEntry(
                seq: UInt64(index + 1),
                date: Self.start.addingTimeInterval(Double(index) + 0.5),
                level: pair.0,
                category: index == 0 ? .bolus : .treatments,
                message: "message \(index)"
            )
        }

        let ack = try await fixture.ingest.ingest(fixture.stage(entries))

        let records = fixture.sink.snapshot()
        #expect(ack == 5)
        #expect(records.map(\.level) == levels.map(\.1))
        #expect(records.map(\.category) == ["Watch/Bolus"] + Array(repeating: "Watch/Treatments", count: 4))
        #expect(records.map(\.timestamp) == entries.map(\.date))
        #expect(records.map(\.message) == entries.map(\.message))
        #expect(records.allSatisfy { $0.file == "Watch" })
    }

    @Test("Repeated and overlapping batches are ingested once per install") func dedupes() async throws {
        let fixture = try Fixture()

        let acks = try await [
            fixture.ingest.ingest(fixture.stage(Self.entries(1 ... 3))),
            fixture.ingest.ingest(fixture.stage(Self.entries(1 ... 3))),
            fixture.ingest.ingest(fixture.stage(Self.entries(2 ... 5))),
            fixture.ingest.ingest(fixture.stage(Self.entries(1 ... 2), installID: "install-b"))
        ]
        #expect(acks == [3, 3, 5, 2])

        let messages = fixture.sink.snapshot().map(\.message)
        #expect(messages == ["entry 1", "entry 2", "entry 3", "entry 4", "entry 5", "entry 1", "entry 2"])

        let sink = fixture.sink
        let relaunched = WatchLogIngest(defaults: fixture.defaults, sink: { sink })
        let ack = try await relaunched.ingest(fixture.stage(Self.entries(4 ... 6)))
        #expect(ack == 6)
        #expect(fixture.sink.snapshot().map(\.message).suffix(1) == ["entry 6"])
    }

    @Test("A cut-off file is acknowledged only up to its last complete entry") func acksParsedEntries() async throws {
        let fixture = try Fixture()
        let url = fixture.directory.appendingPathComponent("cut.jsonl")
        var data = WatchLogEntry.jsonLines(Self.entries(1 ... 3))
        data.append(Data(#"{"seq":4,"lev"#.utf8))
        try data.write(to: url)
        let metadata = Fixture.metadata(Self.entries(1 ... 4), installID: "install-a")
        let batch = try #require(
            WatchLogIngest
                .stage(url, metadata: metadata, into: fixture.directory.appendingPathComponent("staged"))
        )

        let ack = await fixture.ingest.ingest(batch)

        #expect(ack == 3)
        #expect(fixture.sink.snapshot().map(\.message) == ["entry 1", "entry 2", "entry 3"])
    }

    @Test("Staging copies the file and removes it after ingest") func stagesCopy() async throws {
        let fixture = try Fixture()
        let (url, metadata) = try fixture.received(Self.entries(1 ... 2))

        let staging = fixture.directory.appendingPathComponent("staged")
        let batch = try #require(WatchLogIngest.stage(url, metadata: metadata, into: staging))
        try FileManager.default.removeItem(at: url)
        #expect(batch.installID == "install-a")
        #expect(batch.firstSeq == 1 && batch.lastSeq == 2)

        await fixture.ingest.ingest(batch)
        #expect(fixture.sink.snapshot().count == 2)
        #expect(!FileManager.default.fileExists(atPath: batch.file.path))
    }

    @Test("Files without valid metadata or over the size limit are rejected") func rejectsInvalidFiles() throws {
        let fixture = try Fixture()
        let staging = fixture.directory.appendingPathComponent("staged")
        let (url, metadata) = try fixture.received(Self.entries(1 ... 2))

        var wrongVersion = metadata
        wrongVersion[WatchLogTransfer.marker] = 2
        var noInstall = metadata
        noInstall[WatchLogTransfer.installID] = nil
        var reversed = metadata
        reversed[WatchLogTransfer.firstSeq] = NSNumber(value: 5)
        var noLastSeq = metadata
        noLastSeq[WatchLogTransfer.lastSeq] = nil

        for invalid in [nil, [:], wrongVersion, noInstall, reversed, noLastSeq] as [[String: Any]?] {
            #expect(WatchLogIngest.stage(url, metadata: invalid, into: staging) == nil)
        }

        let oversized = fixture.directory.appendingPathComponent("oversized.jsonl")
        try Data(count: WatchLogTransfer.maxFileSize + 1).write(to: oversized)
        #expect(WatchLogIngest.stage(oversized, metadata: metadata, into: staging) == nil)

        let missing = fixture.directory.appendingPathComponent("missing.jsonl")
        #expect(WatchLogIngest.stage(missing, metadata: metadata, into: staging) == nil)
    }

    @Test("Legacy string payloads still become watch records in order") func parsesLegacyLines() {
        let received = Date(timeIntervalSince1970: 2_000_000_000)
        let payload = """
        [2026-01-02T03:04:05+0000] [WatchState.swift:12] send() → first
        no timestamp here

        [2026-01-02T03:04:06+0000] [WatchLogger.swift:40] flush() → third
        """

        let records = WatchLogIngest.legacyRecords(from: payload, receivedAt: received)

        #expect(records.map(\.message) == [
            "[WatchState.swift:12] send() → first",
            "no timestamp here",
            "[WatchLogger.swift:40] flush() → third"
        ])
        #expect(records.allSatisfy { $0.category == "Watch/Legacy" && $0.level == .debug && $0.file == "Watch" })
        #expect(records.map(\.timestamp) == [
            Date(timeIntervalSince1970: 1_767_323_045),
            received,
            Date(timeIntervalSince1970: 1_767_323_046)
        ])
    }
}
