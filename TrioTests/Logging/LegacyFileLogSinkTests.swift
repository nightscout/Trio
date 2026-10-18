import Foundation
import Testing

@testable import Trio

@Suite("Legacy File Log Sink Tests") struct LegacyFileLogSinkTests {
    @Test("Writes lines in order after flush") func testWritesInOrder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sink = LegacyFileLogSink(directory: directory)
        let timestamp = Date()
        for index in 0 ..< 100 {
            sink.accept(LogRecord(
                timestamp: timestamp,
                level: index.isMultiple(of: 2) ? .debug : .warning,
                category: "Service",
                message: "line \(index)",
                file: "File.swift",
                function: "run()",
                line: UInt(index),
                launchID: LaunchID.current
            ))
        }
        await sink.flush()

        let contents = try String(contentsOf: sink.fileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n").map(String.init)
        #expect(lines.count == 100)
        #expect(lines.first?.hasSuffix("[Service] File.swift - run() - 0 - DEV: line 0") == true)
        #expect(lines.dropFirst().first?.hasSuffix("[Service] File.swift - run() - 1 - WARN: line 1") == true)
        #expect(lines.enumerated().allSatisfy { $0.element.hasSuffix("line \($0.offset)") })

        let stamp = try #require(lines.first?.split(separator: " ").first)
        #expect(stamp.contains("."))
    }
}
