import Foundation
import LoopKit
import Testing

@testable import Trio

@Suite("Log Export Tests", .serialized) struct LogExportTests {
    private class StubManager: DeviceManager {
        class var pluginIdentifier: String { "com.example.pump" }
        var localizedTitle: String { "Example Pump" }
        var debugDescription: String { "## StubManager\nserial: SYN-PUMP-0042" }
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
        override class var pluginIdentifier: String { "com.example.cgm" }
        override var localizedTitle: String { "Example CGM" }
        override var debugDescription: String { "## StubCGMManager\nstate: synthetic" }
    }

    private struct Fixture {
        let directory: URL
        let export: LogExport
    }

    private static func makeFixture() async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = DeviceLogStore(
            storageURL: directory.appendingPathComponent("logs/DeviceLog.sqlite"),
            isProtectedDataAvailable: { true }
        )
        await log(store, manager: "com.example.pump", device: "SYN-PUMP-0042", message: "connected to SYN-PUMP-0042")
        await log(store, manager: "com.example.cgm", device: nil, message: "glucose 123")
        await log(store, manager: "com.example.other", device: nil, message: "orphan entry")

        let appLog = InMemoryLogSink()
        appLog.accept(record("upload to https://example-site.test/api/v1/entries", level: .info))
        appLog.accept(record("loop failed", level: .error))
        var stored = SensitiveValues()
        stored.addNightscout(url: "https://example-site.test", secret: nil)
        return Fixture(
            directory: directory,
            export: LogExport(
                appLog: appLog,
                deviceLogStore: store,
                pump: StubManager(),
                cgm: StubCGMManager(),
                storedValues: stored
            )
        )
    }

    private static func log(_ store: DeviceLogStore, manager: String, device: String?, message: String) async {
        await withCheckedContinuation { continuation in
            store.log(managerIdentifier: manager, deviceIdentifier: device, type: .send, message: message) { _ in
                continuation.resume()
            }
        }
    }

    private static func record(_ message: String, level: LogLevel, at date: Date = Date()) -> LogRecord {
        LogRecord(
            timestamp: date,
            level: level,
            category: "Service",
            message: message,
            file: "File.swift",
            function: "run()",
            line: 1,
            launchID: UUID()
        )
    }

    private static func contents(of kind: LogExport.Kind, in fixture: Fixture) async throws -> (name: String, text: String) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try await fixture.export.writeLog(kind, days: 1, into: directory)
        return (url.lastPathComponent, try String(contentsOf: url, encoding: .utf8))
    }

    private static func logLines(_ text: String) -> [String] {
        guard let range = text.range(of: "\n== Log ==\n") else { return [] }
        return text[range.upperBound...].split(separator: "\n").map(String.init)
    }

    private static func sections(_ text: String) -> [String] {
        text.split(separator: "\n").filter { $0.hasPrefix("== ") }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "= ")) }
    }

    @Test("Lines from all sources merge into one time-sorted list across slices") func mergesSources() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let window = DateInterval(start: start, duration: 18 * 60 * 60)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let hour: TimeInterval = 60 * 60
        let lines = [
            LogLine(date: start.addingTimeInterval(7 * hour), source: "Pump", text: "b"),
            LogLine(date: start.addingTimeInterval(1 * hour), source: "Trio", text: "a"),
            LogLine(date: start.addingTimeInterval(13 * hour), source: "CGM", text: "d"),
            LogLine(date: start.addingTimeInterval(7 * hour + 1), source: "Trio", text: "c"),
            LogLine(date: start.addingTimeInterval(6 * hour), source: "Algorithm", text: "boundary"),
            LogLine(date: window.end, source: "Trio", text: "end"),
            LogLine(date: start.addingTimeInterval(-1), source: "Trio", text: "before")
        ]
        var requested: [DateInterval] = []

        try await LogFileWriter.write(header: "Header\n", window: window, to: url, redactor: Redactor(exactValues: [])) { slice in
            requested.append(slice)
            // Every slice sees every line, as an inclusive store query would return the boundary twice
            return Array(lines.reversed())
        }

        let written = try Self.logLines(String(contentsOf: url, encoding: .utf8))
        #expect(requested.count == 3)
        #expect(written.map { $0.split(separator: " ").suffix(2).joined(separator: " ") } == [
            "Trio a", "Algorithm boundary", "Pump b", "Trio c", "CGM d", "Trio end"
        ])
        #expect(written.first?.range(
            of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} [+-]\d{4} Trio a$"#,
            options: .regularExpression
        ) != nil)
    }

    @Test("Trio lines carry a level only for warnings and worse") func levelPrefix() {
        let expected: [(LogLevel, String)] = [
            (.debug, "[Service] message"),
            (.info, "[Service] message"),
            (.notice, "[Service] message"),
            (.warning, "WARNING: [Service] message"),
            (.error, "ERROR: [Service] message"),
            (.fault, "FAULT: [Service] message")
        ]
        for (level, text) in expected {
            let line = LogExport.line(for: Self.record("message", level: level))
            #expect(line.source == "Trio")
            #expect(line.text == text)
        }
    }

    @Test("Shared file is a zip named after the log") func sharesZip() async throws {
        let fixture = try await Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let url = try await fixture.export.makeFile(.pump, days: 1)
        defer { LogExport.discard(url) }
        #expect(url.lastPathComponent.hasPrefix("Trio Pump Logs "))
        #expect(url.pathExtension == "zip")
        let data = try Data(contentsOf: url)
        #expect(Array(data.prefix(4)) == [0x50, 0x4B, 0x03, 0x04])
    }

    @Test("Each file has the sections for its kind") func headerSections() async throws {
        let fixture = try await Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let all = try await Self.contents(of: .all, in: fixture)
        let pump = try await Self.contents(of: .pump, in: fixture)
        let cgm = try await Self.contents(of: .cgm, in: fixture)

        #expect(all.name.hasPrefix("Trio Logs "))
        #expect(pump.name.hasPrefix("Trio Pump Logs "))
        #expect(cgm.name.hasPrefix("Trio CGM Logs "))
        #expect([all.name, pump.name, cgm.name].allSatisfy { $0.hasSuffix(".txt") })
        #expect(Self.sections(all.text) == ["App", "Phone", "Pump", "CGM", "Settings", "Alerts", "Log"])
        #expect(Self.sections(pump.text) == ["App", "Phone", "Pump", "Log"])
        #expect(Self.sections(cgm.text) == ["App", "Phone", "CGM", "Log"])
        #expect(all.text.hasPrefix("Trio Logs\nCreated: "))
        #expect(all.text.contains("\nCovers: last 24 hours\n"))
        #expect(pump.text.contains("Name: Example Pump\nPlugin: com.example.pump\n## StubManager\n"))
    }

    @Test("Pump and CGM files hold only their own device lines") func deviceFilesFilterSources() async throws {
        let fixture = try await Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let pump = try await Self.logLines(Self.contents(of: .pump, in: fixture).text)
        let cgm = try await Self.logLines(Self.contents(of: .cgm, in: fixture).text)
        let all = try await Self.logLines(Self.contents(of: .all, in: fixture).text)

        #expect(pump.count == 1)
        #expect(pump.allSatisfy { $0.contains(" Pump [send] ") })
        #expect(cgm.count == 1)
        #expect(cgm.first?.hasSuffix(" CGM [send] glucose 123") == true)
        #expect(all.count == 5)
        #expect(all.contains { $0.hasSuffix(" com.example.other [send] orphan entry") })
        #expect(all.contains { $0.hasSuffix(" Trio ERROR: [Service] loop failed") })
    }

    @Test("Serials and URLs are replaced in every file") func redactsEveryLine() async throws {
        let fixture = try await Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        for kind in [LogExport.Kind.all, .pump, .cgm] {
            let text = try await Self.contents(of: kind, in: fixture).text
            #expect(!text.contains("SYN-PUMP-0042"))
            #expect(!text.contains("example-site.test"))
        }
        let all = try await Self.contents(of: .all, in: fixture).text
        #expect(all.contains("serial: <device-1>"))
        #expect(all.contains("Pump [send] connected to <device-1>"))
        #expect(all.contains("Trio [Service] upload to <nightscout-url>/api/v1/entries"))
    }
}
