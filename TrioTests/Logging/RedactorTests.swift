import Foundation
import Testing

@testable import Trio

@Suite("Redactor Tests") struct RedactorTests {
    @Test(
        "Patterns replace identifiers",
        arguments: [
            ("upload to https://example-site.test/api/v1/entries failed", "upload to <url-1> failed"),
            ("account demo.user+cgm@example.org linked", "account <email-1> linked"),
            ("Authorization: Bearer abc.DEF-123_xyz", "Authorization: Bearer <secret-1>"),
            ("token 0123456789abcdef0123456789abcdef01234567 sent", "token <secret-1> sent"),
            ("Pod Lot: 123456789 TID: 7654321", "Pod Lot: <pump-serial-1> TID: <pump-serial-2>"),
            ("lot 42424242 paired", "lot <pump-serial-1> paired"),
            ("transmitterID: 8G1ABC connected", "transmitterID: <cgm-serial-1> connected"),
            ("Transmitter 8GXY12 found", "Transmitter <cgm-serial-1> found"),
            ("{\"transmitterID\":\"8G9Z99\"}", "{\"transmitterID\":\"<cgm-serial-1>\"}"),
            ("TID 8GAA11 battery ok", "TID <cgm-serial-1> battery ok"),
            ("* lotNo: 135792468", "* lotNo: <pump-serial-1>"),
            ("* pumpSN: 0a1b2c3d", "* pumpSN: <pump-serial-1>"),
            ("sensorID: Optional(\"DX01AB\")", "sensorID: Optional(\"<cgm-serial-1>\")"),
            ("* deviceName: Optional(\"meter+00042\")", "* deviceName: Optional(\"<serial-1>\")"),
            ("bleNameString: nil", "bleNameString: nil")
        ]
    ) func patterns(input: String, expected: String) {
        #expect(Redactor(exactValues: []).redact(input) == expected)
    }

    @Test(
        "Clinical values, timestamps, UUIDs and plugin identifiers stay untouched",
        arguments: [
            "BG 123 mg/dL",
            "IOB 1.25",
            "2026-10-18T12:00:00.000Z",
            "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
            "DanaKit",
            "com.randallknutson.DanaKit",
            "* 2026-10-18T12:00:00.000Z DanaKit - send rate 0.85 U/h for 30 min",
            "Transmitter battery low"
        ]
    ) func negatives(input: String) {
        #expect(Redactor(exactValues: []).redact(input) == input)
    }

    @Test("Same value gets the same placeholder across inputs") func stablePlaceholders() {
        let redactor = Redactor(exactValues: [])
        let first = redactor.redact("a https://one.example.test b https://two.example.test")
        let second = redactor.redact("c https://two.example.test d https://one.example.test")
        #expect(first == "a <url-1> b <url-2>")
        #expect(second == "c <url-2> d <url-1>")
    }

    @Test("Exact values are replaced before patterns, longest first") func exactValuesFirst() {
        let redactor = Redactor(exactValues: [
            Redactor.ExactValue(value: "my-site.example.test", kind: .host),
            Redactor.ExactValue(value: "https://my-site.example.test/", kind: .url),
            Redactor.ExactValue(value: "synthetic-secret-1", kind: .secret),
            Redactor.ExactValue(value: "DANA-XYZ01", kind: .device),
            Redactor.ExactValue(value: "abc", kind: .device)
        ])
        let output = redactor.redact(
            "GET https://my-site.example.test/api host my-site.example.test secret synthetic-secret-1 device dana-xyz01 abc"
        )
        #expect(output == "GET <url-1>api host <host-1> secret <secret-1> device <device-1> abc")
    }

    @Test("Files are redacted in place and unknown file types are dropped") func redactsFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = directory.appendingPathComponent("Log.txt")
        let binary = directory.appendingPathComponent("Store.sqlite")
        let lines = (0 ..< 20000).map { "line \($0) to https://example.test/x BG 123\n" }.joined()
        try Data(lines.utf8).write(to: text)
        try Data([0, 1, 2]).write(to: binary)

        try Redactor(exactValues: []).redactFiles(in: directory)

        let redacted = try String(contentsOf: text, encoding: .utf8)
        #expect(!redacted.contains("example.test"))
        #expect(redacted.components(separatedBy: "\n").count == 20001)
        #expect(redacted.hasSuffix("line 19999 to <url-1> BG 123\n"))
        #expect(!FileManager.default.fileExists(atPath: binary.path))
    }
}
