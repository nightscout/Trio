import Foundation
import Testing

@testable import Trio

@Suite("Determinations Section Tests") struct DeterminationsSectionTests {
    private static func snapshot(at date: Date, enacted: Bool, glucose: Decimal, reason: String) -> DeterminationSnapshot {
        DeterminationSnapshot(
            id: UUID(),
            deliverAt: date,
            timestamp: date,
            timestampEnacted: enacted ? date : nil,
            enacted: enacted,
            received: enacted,
            isUploadedToNS: false,
            glucose: glucose,
            iob: Decimal(string: "1.25"),
            cob: 12,
            insulinSensitivity: 45,
            sensitivityRatio: Decimal(string: "0.9"),
            currentTarget: 100,
            eventualBG: 140,
            rate: Decimal(string: "0.8"),
            duration: 30,
            temp: "absolute",
            smbToDeliver: Decimal(string: "0.3"),
            insulinReq: Decimal(string: "0.6"),
            carbRatio: 10,
            carbsRequired: 0,
            scheduledBasal: 1,
            reservoir: 100,
            threshold: 70,
            expectedDelta: 2,
            minDelta: 1,
            reason: reason,
            forecasts: ["IOB": [123, 125, 127]]
        )
    }

    @Test("Runs render newest first with a fenced reason") func rendersBullets() throws {
        let older = Self.snapshot(
            at: Date(timeIntervalSince1970: 1_790_000_000),
            enacted: false,
            glucose: 118,
            reason: "COB: 12, Dev: 5; Eventual BG 140 >= 100"
        )
        let newer = Self.snapshot(
            at: Date(timeIntervalSince1970: 1_790_000_300),
            enacted: true,
            glucose: 123,
            reason: "minPredBG 110; temp 0.8 >= 0.75"
        )

        let markdown = DeterminationSnapshot.markdown(for: [older, newer])
        let bullets = markdown.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
        #expect(bullets.count == 2)
        #expect(bullets[0].contains("enacted · glucose 123 · iob 1.25 · cob 12"))
        #expect(bullets[0].contains("rate 0.8 for 30 min · smbToDeliver 0.3 · eventualBG 140 · target 100"))
        #expect(bullets[1].contains("suggested · glucose 118"))
        #expect(markdown.contains("  ```\n  minPredBG 110; temp 0.8 >= 0.75\n  ```"))
        #expect(markdown.hasPrefix("2 runs in window"))
    }

    @Test("Markdown is capped and the cap is noted") func capsRuns() {
        let runs = (0 ..< 5).map {
            Self.snapshot(
                at: Date(timeIntervalSince1970: 1_790_000_000 + Double($0) * 300),
                enacted: true,
                glucose: 100,
                reason: "r"
            )
        }
        let markdown = DeterminationSnapshot.markdown(for: runs, limit: 3)
        #expect(markdown.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }.count == 3)
        #expect(markdown.contains("Showing the newest 3."))
    }

    @Test("Snapshots round-trip through JSON with forecasts") func encodesSnapshot() throws {
        let value = Self.snapshot(at: Date(timeIntervalSince1970: 1_790_000_000), enacted: true, glucose: 123, reason: "r")
        let data = try JSONCoding.encoder.encode([value])
        let decoded = try JSONCoding.decoder.decode([DeterminationSnapshot].self, from: data)
        #expect(decoded.first?.forecasts == ["IOB": [123, 125, 127]])
        #expect(decoded.first?.reason == "r")
        #expect(decoded.first?.deliverAt == value.deliverAt)
    }
}
