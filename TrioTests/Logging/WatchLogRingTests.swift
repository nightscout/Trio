import Foundation
import Testing

@testable import Trio

@Suite("Watch Log Ring Tests") struct WatchLogRingTests {
    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName: String
        let defaults: UserDefaults

        init() {
            suiteName = "WatchLogRingTests.\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suiteName) ?? .standard
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }

        func ring(_ limits: WatchLogRing.Limits = WatchLogRing.Limits()) -> WatchLogRing {
            WatchLogRing(directory: directory, defaults: defaults, limits: limits)
        }

        func segmentFiles() -> [URL] {
            ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "jsonl" }
        }
    }

    private static func drafts(_ count: Int, from start: Date = Date(), message: String = "entry") -> [WatchLogDraft] {
        (0 ..< count).map {
            WatchLogDraft(
                date: start.addingTimeInterval(Double($0)),
                level: .info,
                category: .connectivity,
                message: "\(message) \($0)"
            )
        }
    }

    @Test("Appended entries get increasing seqs and read back in order") func append() {
        let fixture = Fixture()
        let ring = fixture.ring()

        ring.append(Self.drafts(3))
        ring.append(Self.drafts(2, message: "later"))

        let entries = ring.entries(after: 0)
        #expect(entries.map(\.seq) == [1, 2, 3, 4, 5])
        #expect(entries.map(\.message) == ["entry 0", "entry 1", "entry 2", "later 0", "later 1"])
        #expect(ring.entries(after: 3).map(\.seq) == [4, 5])
        #expect(ring.lastSeq == 5)
    }

    @Test("Oldest segments are dropped once over the entry cap") func capsByCount() throws {
        let fixture = Fixture()
        let ring = fixture.ring(WatchLogRing.Limits(maxEntries: 10, segmentEntries: 4))

        ring.append(Self.drafts(25))
        ring.prune()

        let seqs = ring.entries(after: 0).map(\.seq)
        #expect(ring.count <= 10)
        #expect(seqs.last == 25)
        let first = try #require(seqs.first)
        #expect(seqs == Array(first ... 25))
        #expect(fixture.segmentFiles().count == (ring.count + 3) / 4)
    }

    @Test("Oldest segments are dropped once over the size cap") func capsBySize() {
        let fixture = Fixture()
        let ring = fixture.ring(WatchLogRing.Limits(maxBytes: 2000, segmentEntries: 5))

        ring.append(Self.drafts(50, message: String(repeating: "x", count: 60)))
        ring.prune()

        #expect(ring.bytes <= 2000)
        #expect(ring.entries(after: 0).last?.seq == 50)
    }

    @Test("Segments older than the age cap are dropped") func capsByAge() {
        let fixture = Fixture()
        let ring = fixture.ring(WatchLogRing.Limits(maxAge: 60 * 60, segmentEntries: 5))
        let now = Date()

        ring.append(Self.drafts(5, from: now.addingTimeInterval(-3 * 60 * 60)))
        ring.append(Self.drafts(5, from: now.addingTimeInterval(-60)))
        ring.prune(now: now)

        #expect(ring.entries(after: 0).map(\.seq) == [6, 7, 8, 9, 10])

        ring.prune(now: now.addingTimeInterval(2 * 60 * 60))
        #expect(ring.entries(after: 0).isEmpty)
        #expect(fixture.segmentFiles().isEmpty)
    }

    @Test("Seqs and the install ID survive re-creation, even with every segment gone") func persistsAcrossLaunches() throws {
        let fixture = Fixture()
        let first = fixture.ring()
        first.append(Self.drafts(4))
        let installID = first.installID

        let second = fixture.ring()
        second.append(Self.drafts(1, message: "relaunch"))
        #expect(second.installID == installID)
        #expect(second.entries(after: 0).map(\.seq) == [1, 2, 3, 4, 5])

        for file in fixture.segmentFiles() {
            try FileManager.default.removeItem(at: file)
        }
        let third = fixture.ring()
        third.append(Self.drafts(1))
        #expect(third.entries(after: 0).map(\.seq) == [6])
    }

    @Test("An ack moves the unsent window and persists, clamped to what exists") func unsentWindowAfterAck() {
        let fixture = Fixture()
        let ring = fixture.ring()
        ring.append(Self.drafts(6))

        ring.acknowledge(4)
        #expect(ring.entries(after: ring.ackedSeq).map(\.seq) == [5, 6])
        #expect(ring.entries(after: 0).count == 6)

        ring.acknowledge(2)
        #expect(ring.ackedSeq == 4)
        ring.acknowledge(99)
        #expect(ring.ackedSeq == 6)

        #expect(fixture.ring().ackedSeq == 6)
    }

    @Test("A torn final line doesn't swallow later appends") func tornWrite() throws {
        let fixture = Fixture()
        fixture.ring().append(Self.drafts(2))
        let segment = try #require(fixture.segmentFiles().first)
        let handle = try FileHandle(forWritingTo: segment)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"seq":3,"da"#.utf8))
        try handle.close()

        let ring = fixture.ring()
        ring.append(Self.drafts(1, message: "after"))

        #expect(ring.entries(after: 0).map(\.message) == ["entry 0", "entry 1", "after 0"])
        #expect(fixture.segmentFiles().count == 2)
    }
}
