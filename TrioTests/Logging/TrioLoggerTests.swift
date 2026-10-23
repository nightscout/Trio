import Foundation
import Testing

@testable import Trio

@Suite("Trio Logger Tests", .serialized) struct TrioLoggerTests {
    private func capture(_ body: () -> Void) -> [LogRecord] {
        let previous = TrioLogger.sink
        let sink = InMemoryLogSink(capacity: 20000)
        TrioLogger.install(sink)
        defer { TrioLogger.install(previous) }
        body()
        return sink.snapshot().filter { $0.file == "TrioLoggerTests.swift" }
    }

    @Test("Records level, category, file and line for every level") func testRecordsLevels() {
        let token = UUID().uuidString
        let firstLine = UInt(#line) + 2
        let records = capture {
            debug(.algorithm, "debug \(token)")
            info(.loop, "info \(token)")
            warning(.nightscout, "warning \(token)")
            error(.storage, "error \(token)")
            fault(.lifecycle, "fault \(token)")
        }.filter { $0.message.contains(token) }

        #expect(records.map(\.level) == [.debug, .info, .warning, .error, .fault])
        #expect(records.map(\.category) == ["Algorithm", "Loop", "Nightscout", "Storage", "Lifecycle"])
        #expect(records.map(\.line) == Array(firstLine ..< firstLine + 5))
        #expect(records.allSatisfy { $0.file == "TrioLoggerTests.swift" && $0.launchID == LaunchID.current })
        #expect(records.first?.message == "debug \(token)")
    }

    @Test("Error returns to the caller") func testErrorReturns() {
        var reached = false
        _ = capture {
            error(.loop, "error returns", description: "detail")
            reached = true
        }
        #expect(reached)
    }

    @Test("Debug without console output still reaches the sink") func testPrintToConsoleFalse() {
        let records = capture {
            debug(.ui, "quiet", printToConsole: false)
        }
        #expect(records.last?.message == "quiet")
    }

    @Test("10 000 debug calls stay cheap") func testDebugThroughput() {
        let clock = ContinuousClock()
        var elapsed: Duration = .zero
        let records = capture {
            elapsed = clock.measure {
                for index in 0 ..< 10000 {
                    debug(.loop, "throughput \(index)")
                }
            }
        }
        print("10 000 debug calls took \(elapsed)")
        #expect(records.count == 10000)
        #expect(elapsed < .milliseconds(500))
    }

    @Test("In-memory sink keeps only the newest records") func testRingBuffer() {
        let sink = InMemoryLogSink(capacity: 3)
        for index in 0 ..< 5 {
            sink.accept(LogRecord(
                timestamp: Date(),
                level: .debug,
                category: "Loop",
                message: "\(index)",
                file: "File.swift",
                function: "f()",
                line: 1,
                launchID: LaunchID.current
            ))
        }
        #expect(sink.snapshot().map(\.message) == ["2", "3", "4"])
    }

    @Test("Timestamps strictly increase in call order") func testIncreasingTimestamps() {
        let records = capture {
            for index in 0 ..< 5000 {
                debug(.loop, "tick \(index)", printToConsole: false)
            }
        }
        let stamps = records.filter { $0.message.hasPrefix("tick ") }.map(\.timestamp)
        #expect(stamps.count == 5000)
        #expect(zip(stamps, stamps.dropFirst()).allSatisfy { $0 < $1 })
    }
}
