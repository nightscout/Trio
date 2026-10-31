import CryptoKit
import Foundation
import Testing

@testable import Trio

@Suite("Redactor Tests") struct RedactorTests {
    private static func redactor(_ fill: (inout SensitiveValues) -> Void) -> Redactor {
        var values = SensitiveValues()
        fill(&values)
        return Redactor(exactValues: values.values)
    }

    private static func redactor(rawState: [String: Any], plugin: String) -> Redactor {
        redactor { $0.add(rawState: rawState, pluginIdentifier: plugin) }
    }

    @Test("Nightscout address, host, secret and its hash are replaced in every form") func nightscout() {
        let secret = "synthetic secret/0001!"
        let hash = Insecure.SHA1.hash(data: Data(secret.utf8)).map { String(format: "%02x", $0) }.joined()
        let redactor = Self.redactor { $0.addNightscout(url: "https://my-site.example.test/", secret: secret) }
        let cases = [
            ("GET https://my-site.example.test/api/v1/entries", "GET <nightscout-url>/api/v1/entries"),
            ("GET HTTPS://MY-SITE.EXAMPLE.TEST/api", "GET <nightscout-url>/api"),
            ("ping https://my-site.example.test failed", "ping <nightscout-url> failed"),
            ("host my-site.example.test unreachable", "host <nightscout-host> unreachable"),
            ("{\"url\":\"https:\\/\\/my-site.example.test\\/api\"}", "{\"url\":\"https:\\/\\/<nightscout-host>\\/api\"}"),
            ("next=https%3A%2F%2Fmy-site.example.test%2Fapi", "next=<nightscout-url>%2Fapi"),
            ("secret \(secret) set", "secret <api-secret> set"),
            ("token=synthetic%20secret%2F0001%21 sent", "token=<api-secret> sent"),
            ("body secret=synthetic+secret%2f0001%21", "body secret=<api-secret>"),
            ("api-secret: \(hash.uppercased())", "api-secret: <api-secret>")
        ]
        for (input, expected) in cases {
            #expect(redactor.redact(input) == expected)
        }
    }

    @Test("Trio's own identifiers are replaced") func trioIdentifiers() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        defaults.set("synthetic-remote-secret", forKey: "trioRemoteControlSharedSecret")
        defaults.set("00aa11bb22cc33dd44ee55ff", forKey: "deviceToken")
        let redactor = Self.redactor { $0.addTrioIdentifiers(defaults: defaults) }
        #expect(redactor.redact("secret synthetic-remote-secret") == "secret <remote-secret>")
        #expect(redactor.redact("push to 00AA11BB22CC33DD44EE55FF") == "push to <push-token>")
    }

    @Test("Stored pump and CGM identifiers are replaced") func deviceState() {
        let cases: [(String, [String: Any], String, String)] = [
            (
                "Omni",
                ["podState": ["lotNo": 135_792_468, "lotSeq": 2_468_013, "address": 0x1F0E_89F0]],
                "Pod Lot: 135792468 TID: 2468013 address 1F0E89F0",
                "Pod Lot: <pump-serial-1> TID: <pump-serial-2> address <device-1>"
            ),
            ("Omni", ["previousPodState": ["lotNo": 135_792_469]], "* lotNo: 135792469", "* lotNo: <pump-serial-1>"),
            ("Minimed500", ["pumpID": "654321"], "pumpID 654321 ok", "pumpID <pump-serial-1> ok"),
            (
                "Dana",
                ["deviceName": "SYN00042AB", "pairingKey": Data([0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6])],
                "name: SYN00042AB key a1b2c3d4e5f6",
                "name: <pump-serial-1> key <secret-1>"
            ),
            (
                "Medtrum",
                ["pumpSN": Data([0x0A, 0x1B, 0x2C, 0x3D])],
                "pumpSN: 0A1B2C3D adv 3d2c1b0a",
                "pumpSN: <pump-serial-1> adv <pump-serial-2>"
            ),
            ("DexG6Transmitter", ["transmitterID": "8GSYN1"], "Transmitter 8GSYN1 found", "Transmitter <cgm-serial-1> found"),
            (
                "G7CGMManager",
                ["sensorID": "DXCMS1", "previousSensor": ["sensorID": "DXCMS0", "pairingCode": "1234"]],
                "sensorID: DXCMS1 previousSensor: [\"pairingCode\": \"1234\", \"sensorID\": \"DXCMS0\"]",
                "sensorID: <cgm-serial-1> previousSensor: [<secret-1>, \"sensorID\": \"<cgm-serial-2>\"]"
            ),
            (
                "G7CGMManager",
                ["shareUsername": "synthetic.follower"],
                "Signed in to Dexcom Share as synthetic.follower",
                "Signed in to Dexcom Share as <account-1>"
            ),
            (
                "LibreLoopCGMManager",
                ["sensorSerial": "SYN0LIBRE3", "bleAddress": "aa:bb:cc:dd:ee:01"],
                "serial=SYN0LIBRE3 bleAddress=aa:bb:cc:dd:ee:01 name=AABBCCDDEE01",
                "serial=<cgm-serial-1> bleAddress=<device-1> name=<device-2>"
            ),
            (
                "TandemPumpManager",
                [
                    "pumpState": [
                        "pumpSerial": 11_223_344,
                        "pcbSerialNumber": 55_667_788,
                        "peripheralUuid": "8C1D2E3F-0000-4000-8000-00000000AB12",
                        "pincode": "SYNPIN123456",
                        "derivedSecret": Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04]),
                        "serverNonce": Data([0xFB, 0xFF, 0x10, 0x20, 0x30, 0x40, 0x50, 0x60])
                    ]
                ],
                "pumpSerial: Optional(11223344) pcb 55667788 uuid 8C1D2E3F-0000-4000-8000-00000000AB12 pin SYNPIN123456 derivedSecret: Optional(\"3q2+7wECAwQ=\") serverNonce: Optional(\"+/8QIDBAUGA=\") hex deadbeef01020304",
                "pumpSerial: Optional(<pump-serial-1>) pcb <pump-serial-2> uuid <device-1> pin <secret-1> derivedSecret: Optional(\"<secret-2>\") serverNonce: Optional(\"<secret-3>\") hex <secret-4>"
            ),
            (
                "SyaiCGMManager",
                ["sensors": ["activeMAC": "AABBCCDDEE02", "pendingBind": ["mac": "AABBCCDDEE03"]]],
                "activeMAC: AABBCCDDEE02 pendingBind: AABBCCDDEE03",
                "activeMAC: <device-1> pendingBind: <device-2>"
            ),
            (
                "EversenseKit",
                ["bleNameString": "SYN-EVR-01", "accessToken": "synthetic-access-token"],
                "Connecting to: SYN-EVR-01 with synthetic-access-token",
                "Connecting to: <cgm-serial-1> with <secret-1>"
            ),
            (
                "AccuChek",
                ["sensorInfo": ["serialNumber": "SYNACC0001"], "pinCode": "987654"],
                "serialNumber: SYNACC0001 pin 987654",
                "serialNumber: <cgm-serial-1> pin <secret-1>"
            )
        ]
        for (plugin, rawState, input, expected) in cases {
            #expect(Self.redactor(rawState: rawState, plugin: plugin).redact(input) == expected, "\(plugin)")
        }
    }

    @Test("Remote command senders and Eversense fleet secrets are replaced in transit") func inTransit() {
        let redactor = Redactor(exactValues: [])
        #expect(
            redactor.redact("Remote command processed successfully. User: Synthetic Caregiver. Command Type: Bolus. ")
                == "Remote command processed successfully. User: <remote-user-1>. Command Type: Bolus. "
        )
        #expect(redactor.redact("Fleet secret: {\"key\":\"c2VjcmV0\"}\nnext") == "Fleet secret: <secret-1>\nnext")
    }

    @Test(
        "Packet dumps, clinical values, timestamps, UUIDs and plugin identifiers stay untouched",
        arguments: [
            "Sending data - Name: CMD_7, OpCode: 7, Encoded data: a5a50c01c86e2a4b9d0f3e771122334455665a5a",
            "Pump [receive] 0123456789abcdef0123456789abcdef01234567",
            "send 1f0e89f00a1d0302abcd",
            "BG 123 mg/dL, delta -4, IOB 1.25, lot 1357924680",
            "2026-10-18T12:00:00.000Z 2026-10-18 14:00:00.000 +0200",
            "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
            "com.randallknutson.DanaKit DexG6Transmitter G7CGMManager",
            "Transmitter paired",
            "TID search started"
        ]
    ) func untouched(input: String) {
        let redactor = Self.redactor {
            $0.add(rawState: ["podState": ["lotNo": 135_792_468, "address": 0x1F0E_89F0]], pluginIdentifier: "Omni")
            $0.add(rawState: ["pairingKey": Data([0xC8, 0x6E, 0x2A, 0x4B, 0x9D, 0x0F])], pluginIdentifier: "Dana")
            $0.add(rawState: ["transmitterID": "8GSYN1"], pluginIdentifier: "DexG6Transmitter")
            $0.add("abc", .device)
        }
        #expect(redactor.redact(input) == input)
    }

    @Test("Same value gets the same placeholder across inputs") func stablePlaceholders() {
        let redactor = Redactor(exactValues: [
            Redactor.ExactValue(value: "SYN-DEV-0001", kind: .device),
            Redactor.ExactValue(value: "SYN-DEV-0002", kind: .device),
            Redactor.ExactValue(value: "synthetic.user@example.test", kind: .email)
        ])
        #expect(redactor.redact("a SYN-DEV-0002 b syn-dev-0001") == "a <device-1> b <device-2>")
        #expect(
            redactor
                .redact("c SYN-DEV-0001 d SYN-DEV-0002 synthetic.user@example.test") == "c <device-2> d <device-1> <email-1>"
        )
    }

    @Test("Longest value wins where values overlap") func longestFirst() {
        let redactor = Self.redactor {
            $0.addNightscout(url: "https://my-site.example.test", secret: nil)
            $0.add("DANA-XYZ01", .device)
        }
        #expect(
            redactor.redact("GET https://my-site.example.test/api host my-site.example.test device dana-xyz01")
                == "GET <nightscout-url>/api host <nightscout-host> device <device-1>"
        )
    }
}

@Suite("Redactor Throughput") struct RedactorThroughputTests {
    private static let lines = [
        "2026-10-18 12:00:00.123 +0000 Trio [Nightscout] Uploaded 12 glucose values to https://synthetic-site.example.test/api/v1/entries.json",
        "2026-10-18 12:00:01.456 +0000 Pump [send] a5c3f0010203040506070809aabbccddeeff00112233",
        "2026-10-18 12:00:01.789 +0000 Pump [receive] 0123456789abcdef0123456789abcdef01234567",
        "2026-10-18 12:00:02.000 +0000 Algorithm enacted · BG 123 · IOB 1.25 · COB 12 · rate 0.85/30m · eventual 110",
        "2026-10-18 12:00:03.000 +0000 CGM [trace] [G7CGMManager] Sensor DXSYN1 reading 123 mg/dL trend 1.2",
        "2026-10-18 12:00:04.000 +0000 Trio [APS] Loop started, 3F2504E0-4F89-11D3-9A0C-0305E82C3301 at 2026-10-18T12:00:04.000Z",
        "2026-10-18 12:00:05.000 +0000 Pump [connection] Connected to SYNDANA01 rssi -61"
    ]

    @Test(
        "Redacts at least 20 MB/s",
        .enabled(if: ProcessInfo.processInfo.environment["TRIO_STRESS"] == "1")
    ) func throughput() {
        var chunk = ""
        var index = 0
        while chunk.utf8.count < 64 * 1024 {
            chunk += Self.lines[index % Self.lines.count] + "\n"
            index += 1
        }
        let chunks = (0 ..< 50 * 1024 * 1024 / chunk.utf8.count).map { "\($0) " + chunk }
        let redactor = Redactor(exactValues: [
            Redactor.ExactValue(value: "https://synthetic-site.example.test", kind: .nightscoutURL),
            Redactor.ExactValue(value: "synthetic-site.example.test", kind: .nightscoutHost),
            Redactor.ExactValue(value: "synthetic-secret-value", kind: .apiSecret),
            Redactor.ExactValue(value: "SYNDANA01", kind: .device),
            Redactor.ExactValue(value: "DXSYN1", kind: .device)
        ])
        let bytes = chunks.reduce(0) { $0 + $1.utf8.count }
        let start = Date()
        var output = 0
        for chunk in chunks {
            output += redactor.redact(chunk).utf8.count
        }
        let rate = Double(bytes) / 1_048_576 / Date().timeIntervalSince(start)
        print("Redactor throughput: \(String(format: "%.1f", rate)) MB/s over \(bytes / 1_048_576) MB")
        #expect(output > 0)
        #expect(rate >= 20)
    }
}
