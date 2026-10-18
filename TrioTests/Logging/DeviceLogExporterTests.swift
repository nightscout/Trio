import Foundation
import LoopKit
import Testing

@testable import Trio

@Suite("Device Log Exporter Tests", .serialized) struct DeviceLogExporterTests {
    private class StubManager: DeviceManager {
        class var pluginIdentifier: String { "com.example.pump" }
        var localizedTitle: String { "Example Pump" }
        var debugDescription: String { "## StubManager\nstate: synthetic" }
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
    }

    private struct Fixture {
        let directory: URL
        let output: URL
        let store: DeviceLogStore
        let exporter: DeviceLogExporter
    }

    private static func makeFixture(managers: [DeviceManager] = [StubManager(), StubCGMManager()]) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let output = directory.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let store = DeviceLogStore(
            storageURL: directory.appendingPathComponent("logs/DeviceLog.sqlite"),
            isProtectedDataAvailable: { true }
        )
        let exporter = DeviceLogExporter(
            store: store,
            documentsDirectory: directory.appendingPathComponent("Documents", isDirectory: true),
            managers: { managers }
        )
        return Fixture(directory: directory, output: output, store: store, exporter: exporter)
    }

    private static func log(_ store: DeviceLogStore, manager: String, device: String?, message: String) async {
        await withCheckedContinuation { continuation in
            store.log(managerIdentifier: manager, deviceIdentifier: device, type: .send, message: message) { _ in
                continuation.resume()
            }
        }
    }

    private static func seed(_ store: DeviceLogStore) async {
        await log(store, manager: "com.example.pump", device: "device-1", message: "pump one")
        await log(store, manager: "com.example.cgm", device: nil, message: "cgm one")
        await log(store, manager: "com.example.pump", device: "device-1", message: "pump two")
        await log(store, manager: "com.example.orphan", device: "device-2", message: "orphan one")
    }

    private static var recentWindow: DateInterval {
        DateInterval(start: Date().addingTimeInterval(-3 * 24 * 60 * 60), end: Date().addingTimeInterval(60))
    }

    private static func request(
        window: DateInterval = recentWindow,
        managerIdentifier: String? = nil,
        includeKitFiles: Bool = false
    ) -> DeviceLogExportRequest {
        DeviceLogExportRequest(
            window: window,
            managerIdentifier: managerIdentifier,
            includeOSLog: false,
            includeKitFiles: includeKitFiles
        )
    }

    private static func files(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    private static func entryLines(_ url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("* ") }
    }

    @Test("Exporting all writes one file per identifier") func exportsAll() async throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        await Self.seed(fixture.store)

        try await fixture.exporter.export(Self.request(), into: fixture.output)

        #expect(try Self.files(in: fixture.output) == [
            "DeviceLog-com.example.cgm.txt",
            "DeviceLog-com.example.orphan.txt",
            "DeviceLog-com.example.pump.txt"
        ])

        let pumpURL = fixture.output.appendingPathComponent("DeviceLog-com.example.pump.txt")
        let pump = try String(contentsOf: pumpURL, encoding: .utf8)
        #expect(pump.hasPrefix("# Example Pump (com.example.pump)\n\n```\n## StubManager\nstate: synthetic\n```\n"))

        let pumpLines = try Self.entryLines(pumpURL)
        #expect(pumpLines.count == 2)
        #expect(pumpLines.allSatisfy {
            $0.range(
                of: #"^\* \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z com\.example\.pump device-1 send pump (one|two)$"#,
                options: .regularExpression
            ) != nil
        })
        #expect(pumpLines.first?.hasSuffix("pump one") == true)

        let cgmLines = try Self.entryLines(fixture.output.appendingPathComponent("DeviceLog-com.example.cgm.txt"))
        #expect(cgmLines.count == 1)
        #expect(cgmLines.first?.hasSuffix(" com.example.cgm - send cgm one") == true)

        let orphanURL = fixture.output.appendingPathComponent("DeviceLog-com.example.orphan.txt")
        #expect(try String(contentsOf: orphanURL, encoding: .utf8).hasPrefix("# com.example.orphan\n"))
        #expect(try Self.entryLines(orphanURL).count == 1)
    }

    @Test("Exporting one identifier writes only its file") func exportsOne() async throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        await Self.seed(fixture.store)

        try await fixture.exporter.export(Self.request(managerIdentifier: "com.example.cgm"), into: fixture.output)

        #expect(try Self.files(in: fixture.output) == ["DeviceLog-com.example.cgm.txt"])
        #expect(try Self.entryLines(fixture.output.appendingPathComponent("DeviceLog-com.example.cgm.txt")).count == 1)
    }

    @Test("Stored entries export without a live manager") func exportsWithoutLiveManager() async throws {
        let fixture = try Self.makeFixture(managers: [])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        await Self.seed(fixture.store)

        try await fixture.exporter.export(Self.request(managerIdentifier: "com.example.pump"), into: fixture.output)

        let url = fixture.output.appendingPathComponent("DeviceLog-com.example.pump.txt")
        #expect(try Self.files(in: fixture.output) == ["DeviceLog-com.example.pump.txt"])
        #expect(try String(contentsOf: url, encoding: .utf8).hasPrefix("# com.example.pump\n"))
        #expect(try Self.entryLines(url).count == 2)
    }

    @Test("Entries outside the window are skipped") func filtersWindow() async throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        await Self.seed(fixture.store)

        let past = DateInterval(start: Date().addingTimeInterval(-2 * 24 * 60 * 60), end: Date().addingTimeInterval(-60 * 60))
        try await fixture.exporter.export(Self.request(window: past), into: fixture.output)

        #expect(try Self.files(in: fixture.output) == ["DeviceLog-com.example.cgm.txt", "DeviceLog-com.example.pump.txt"])
        #expect(try Self.entryLines(fixture.output.appendingPathComponent("DeviceLog-com.example.pump.txt")).isEmpty)
        #expect(try Self.entryLines(fixture.output.appendingPathComponent("DeviceLog-com.example.cgm.txt")).isEmpty)
    }

    @Test("Kit files are copied with a prefix") func copiesKitFiles() async throws {
        let fixture = try Self.makeFixture(managers: [])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let kitDirectory = fixture.directory.appendingPathComponent("Documents/danakit", isDirectory: true)
        try FileManager.default.createDirectory(at: kitDirectory, withIntermediateDirectories: true)
        try Data("synthetic".utf8).write(to: kitDirectory.appendingPathComponent("log.txt"))

        try await fixture.exporter.export(Self.request(includeKitFiles: true), into: fixture.output)

        #expect(try Self.files(in: fixture.output) == ["Kit-danakit-log.txt"])
    }
}
