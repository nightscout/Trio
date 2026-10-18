import Foundation
import Testing

@testable import Trio

@Suite("Diagnostic Report Generator Tests") struct DiagnosticReportGeneratorTests {
    private struct FakeSection: DiagnosticReportSection {
        let title: String
        let order: Int
        var delay: TimeInterval = 0
        var sideFile: String?

        func render(window _: DateInterval, into directory: URL) async -> String {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            if let sideFile {
                try? Data("contact admin@example.com\n".utf8).write(to: directory.appendingPathComponent(sideFile))
            }
            return "body of \(title)"
        }
    }

    private static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static let window = DateInterval(start: Date(timeIntervalSince1970: 1_790_000_000), duration: 3 * 24 * 60 * 60)

    @Test("Sections are ordered and a slow section times out") func orderingAndTimeout() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let generator = DiagnosticReportGenerator(sectionTimeout: 0.3, sections: { _ in
            [
                FakeSection(title: "Third", order: 30),
                FakeSection(title: "Slow", order: 20, delay: 5, sideFile: "Slow.txt"),
                FakeSection(title: "First", order: 10, sideFile: "First.txt")
            ]
        })

        let started = Date()
        let markdown = try await generator.generate(window: Self.window, includeDebug: true, into: directory)
        #expect(Date().timeIntervalSince(started) < 3)

        let headings = markdown.components(separatedBy: "\n").filter { $0.hasPrefix("## ") }
        #expect(headings == ["## First", "## Slow", "## Third"])
        #expect(markdown.contains("## Slow\n\n_timed out_"))
        #expect(markdown.contains("body of First"))
        #expect(markdown.hasPrefix("# Trio Report"))
        #expect(markdown.contains("Window: "))

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.contains("First.txt"))
        #expect(!files.contains("Slow.txt"))
        #expect(files.contains { $0.hasPrefix("Trio Report ") && $0.hasSuffix(".md") })
    }

    @Test("Side files and Markdown are redacted") func redactsBundle() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let generator = DiagnosticReportGenerator(
            sectionTimeout: 2,
            sections: { _ in [FakeSection(title: "Device ABC-1234", order: 0, sideFile: "Side.txt")] },
            exactValues: { _ in [Redactor.ExactValue(value: "ABC-1234", kind: .device)] }
        )

        let markdown = try await generator.generate(window: Self.window, includeDebug: false, into: directory)
        #expect(markdown.contains("## Device <device-1>"))
        #expect(!markdown.contains("ABC-1234"))

        let side = try String(contentsOf: directory.appendingPathComponent("Side.txt"), encoding: .utf8)
        #expect(side == "contact <email-1>\n")
    }
}
