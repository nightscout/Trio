import Foundation
import Testing

@testable import Trio

@Suite("Watch Log Ingest Tests") struct WatchLogIngestTests {
    @Test("Each payload line becomes a watch record in order") func parsesLines() {
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
