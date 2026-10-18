import Foundation
import Testing

@testable import Trio

@Suite("Diagnostic Archiver Tests") struct DiagnosticArchiverTests {
    @Test("Zips a directory into a valid archive") func testZipDirectory() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        try Data("first".utf8).write(to: directory.appendingPathComponent("first.txt"))
        try Data("second".utf8).write(to: directory.appendingPathComponent("second.txt"))

        let archive = try DiagnosticArchiver.zip(directory, name: "archiver-test-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: archive) }

        #expect(fileManager.fileExists(atPath: archive.path))
        #expect(archive.pathExtension == "zip")
        let data = try Data(contentsOf: archive)
        #expect(data.count > 22)
        #expect(Array(data.prefix(4)) == [0x50, 0x4B, 0x03, 0x04])
    }
}
