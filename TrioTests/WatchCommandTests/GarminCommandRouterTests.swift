import Foundation
import Testing

@testable import Trio

@Suite("Garmin Command Router Tests") struct GarminCommandRouterTests {
    let requestID = "3f2b8c1e-4a5d-4e6f-9a7b-1c2d3e4f5a6b"
    let appUUID = UUID()
    let milliseconds: UInt64 = 1_800_000_000_123

    private func envelope(command: String, payload: [String: Any]) -> [String: Any] {
        [
            "v": 1,
            "req": "command",
            "requestId": requestID,
            "date": NSNumber(value: milliseconds),
            "command": command,
            "payload": payload
        ]
    }

    private func parsedCommand(_ message: Any) -> WatchCommand? {
        guard case let .command(_, _, _, command) = GarminCommandEnvelope.parse(message) else { return nil }
        return command
    }

    // MARK: - Parsing

    @Test("Bare status string is the legacy status request") func testLegacyStatus() {
        #expect(GarminCommandEnvelope.parse("status") == .legacyStatus)
        #expect(GarminCommandEnvelope.parse("bolus") == .invalid(requestID: nil))
    }

    @Test("v1 status and presets requests carry no other fields") func testReadRequests() {
        #expect(GarminCommandEnvelope.parse(["v": 1, "req": "status"]) == .status)
        #expect(GarminCommandEnvelope.parse(["v": 1, "req": "presets"]) == .presets)
        #expect(GarminCommandEnvelope.parse(["v": 1, "req": "presets", "extra": true]) == .invalid(requestID: nil))
        #expect(GarminCommandEnvelope.parse(["v": 2, "req": "status"]) == .invalid(requestID: nil))
        #expect(GarminCommandEnvelope.parse(["v": "1", "req": "status"]) == .invalid(requestID: nil))
        #expect(GarminCommandEnvelope.parse(["v": true, "req": "status"]) == .invalid(requestID: nil))
    }

    @Test("Every phase-1 command parses with its exact payload") func testCommands() {
        #expect(parsedCommand(envelope(command: "bolus", payload: ["bolus": 1.5])) == .bolus(1.5))
        #expect(parsedCommand(envelope(command: "bolus", payload: ["bolus": 2])) == .bolus(2))
        #expect(parsedCommand(envelope(command: "carbs", payload: ["carbs": 45])) == .carbs(45))
        #expect(
            parsedCommand(envelope(command: "mealBolus", payload: ["carbs": 45, "bolus": 3.25]))
                == .mealBolus(carbs: 45, bolus: 3.25)
        )
        #expect(
            parsedCommand(envelope(command: "activateOverride", payload: ["name": "Sport"])) ==
                .activateOverride(name: "Sport")
        )
        #expect(parsedCommand(envelope(command: "cancelOverride", payload: [:])) == .cancelOverride)
        #expect(
            parsedCommand(envelope(command: "activateTempTarget", payload: ["name": "Walk"])) == .activateTempTarget(name: "Walk")
        )
        #expect(parsedCommand(envelope(command: "cancelTempTarget", payload: [:])) == .cancelTempTarget)
    }

    @Test("The command date is read as Unix milliseconds") func testDate() {
        guard case let .command(echoedID, uuid, date, _) = GarminCommandEnvelope.parse(
            envelope(command: "cancelOverride", payload: [:])
        ) else {
            Issue.record("Expected a command")
            return
        }
        #expect(echoedID == requestID)
        #expect(uuid == UUID(uuidString: requestID))
        #expect(abs(date.timeIntervalSince1970 - 1_800_000_000.123) < 0.000_1)
    }

    @Test("A Monkey C Float bolus is rounded to 0.001 U") func testFloatRounding() {
        let payload: [String: Any] = ["bolus": NSNumber(value: Float(0.1))]
        #expect(parsedCommand(envelope(command: "bolus", payload: payload)) == .bolus(Decimal(string: "0.1")!))
    }

    @Test("Malformed commands are rejected but keep their request ID for the ack") func testMalformedPayloads() {
        let cases: [(command: String, payload: [String: Any])] = [
            ("bolus", ["bolus": true]),
            ("bolus", ["bolus": "1"]),
            ("bolus", ["bolus": 1, "note": "x"]),
            ("bolus", [:]),
            ("carbs", ["carbs": 12.5]),
            ("carbs", ["carbs": "12"]),
            ("mealBolus", ["carbs": 20]),
            ("activateOverride", ["name": 3]),
            ("activateOverride", [:]),
            ("cancelOverride", ["name": "Sport"]),
            ("requestBolusRecommendation", [:]),
            ("unknown", [:])
        ]
        for (command, payload) in cases {
            #expect(
                GarminCommandEnvelope.parse(envelope(command: command, payload: payload)) == .invalid(requestID: requestID),
                "\(command) with \(payload.keys.sorted())"
            )
        }
    }

    @Test("Malformed envelopes are rejected") func testMalformedEnvelopes() {
        var extraField = envelope(command: "cancelOverride", payload: [:])
        extraField["auth"] = ["scheme": "hmac-sha256"]
        #expect(GarminCommandEnvelope.parse(extraField) == .invalid(requestID: requestID))

        var missingDate = envelope(command: "cancelOverride", payload: [:])
        missingDate["date"] = nil
        #expect(GarminCommandEnvelope.parse(missingDate) == .invalid(requestID: requestID))

        var negativeDate = envelope(command: "cancelOverride", payload: [:])
        negativeDate["date"] = -1
        #expect(GarminCommandEnvelope.parse(negativeDate) == .invalid(requestID: requestID))

        var badPayload = envelope(command: "cancelOverride", payload: [:])
        badPayload["payload"] = "none"
        #expect(GarminCommandEnvelope.parse(badPayload) == .invalid(requestID: requestID))

        var wrongVersion = envelope(command: "cancelOverride", payload: [:])
        wrongVersion["v"] = 2
        #expect(GarminCommandEnvelope.parse(wrongVersion) == .invalid(requestID: requestID))
    }

    @Test("Request IDs must be RFC 4122 UUIDs") func testRequestIDFormat() {
        #expect(GarminCommandEnvelope.rfc4122UUID(requestID) != nil)
        #expect(GarminCommandEnvelope.rfc4122UUID(requestID.uppercased()) != nil)
        // variant nibble 'c' is the Microsoft layout, not RFC 4122
        #expect(GarminCommandEnvelope.rfc4122UUID("3f2b8c1e-4a5d-4e6f-ca7b-1c2d3e4f5a6b") == nil)
        #expect(GarminCommandEnvelope.rfc4122UUID("3f2b8c1e4a5d4e6f9a7b1c2d3e4f5a6b") == nil)
        #expect(GarminCommandEnvelope.rfc4122UUID("not-a-uuid") == nil)
    }

    // MARK: - Routing

    @Test("Status requests refresh the broadcast state and send no reply") func testStatusRouting() async {
        let router = GarminCommandRouter(processor: SpyWatchCommandProcessor())

        let messages: [Any] = ["status", ["v": 1, "req": "status"] as [String: Any]]
        for message in messages {
            let outcome = await router.route(message, from: appUUID, isRegistered: true, appName: "test")
            #expect(outcome.reply == nil)
            #expect(outcome.refreshTrigger == "WatchRequest")
        }
    }

    @Test("Unregistered apps are ignored without executing") func testUnregisteredApp() async {
        let processor = SpyWatchCommandProcessor()
        let router = GarminCommandRouter(processor: processor)

        let outcome = await router.route(
            envelope(command: "carbs", payload: ["carbs": 10]),
            from: appUUID,
            isRegistered: false,
            appName: "test"
        )

        #expect(outcome.reply == nil)
        #expect(outcome.refreshTrigger == nil)
        #expect(processor.processed.isEmpty)
    }

    @Test("A command gets exactly the v1 ack and triggers a refresh on success") func testCommandAck() async throws {
        let processor = SpyWatchCommandProcessor()
        let router = GarminCommandRouter(processor: processor)

        let outcome = await router.route(
            envelope(command: "carbs", payload: ["carbs": 10]),
            from: appUUID,
            isRegistered: true,
            appName: "test"
        )

        let reply = try #require(outcome.reply)
        #expect(Set(reply.keys) == ["v", "req", "requestId", "acknowledged", "ackCode", "message"])
        #expect(reply["v"] as? Int == 1)
        #expect(reply["req"] as? String == "ack")
        #expect(reply["requestId"] as? String == requestID)
        #expect(reply["acknowledged"] as? Bool == true)
        #expect(reply["ackCode"] as? String == "carbs_logged")
        #expect(outcome.refreshTrigger == "WatchCommand")

        #expect(processor.processed.count == 1)
        #expect(processor.processed.first?.appUUID == appUUID)
        #expect(processor.processed.first?.command == .carbs(10))
    }

    @Test("Failures do not refresh; partial failures do") func testRefreshRules() async {
        let processor = SpyWatchCommandProcessor()
        let router = GarminCommandRouter(processor: processor)
        let message = envelope(command: "mealBolus", payload: ["carbs": 10, "bolus": 1])

        processor.result = .failure("Watch commands are disabled.")
        let failed = await router.route(message, from: appUUID, isRegistered: true, appName: "test")
        #expect(failed.refreshTrigger == nil)
        #expect(failed.reply?["ackCode"] as? String == "failure")

        processor.result = WatchCommandResult(acknowledged: false, ackCode: .partialFailure, message: "Carbs logged.")
        let partial = await router.route(message, from: appUUID, isRegistered: true, appName: "test")
        #expect(partial.refreshTrigger == "WatchCommand")
        #expect(partial.reply?["ackCode"] as? String == "partial_failure")
    }

    @Test("A preset request gets a targeted presets reply and no broadcast refresh") func testPresetsReply() async throws {
        let processor = SpyWatchCommandProcessor()
        processor.presetsResult = WatchCommandPresets(
            overridePresets: [OverridePresetWatch(name: "Sport", isEnabled: true)],
            tempTargetPresets: [TempTargetPresetWatch(name: "Walk", isEnabled: false)],
            capabilities: WatchCommandCapabilities(
                isCommandControlEnabled: true,
                isBolusCommandEnabled: false,
                maxBolus: 5,
                maxCarbs: 120,
                bolusIncrement: 0.05
            )
        )
        let router = GarminCommandRouter(processor: processor)

        let outcome = await router.route(["v": 1, "req": "presets"], from: appUUID, isRegistered: true, appName: "test")

        let reply = try #require(outcome.reply)
        #expect(Set(reply.keys) == [
            "v", "req", "overridePresets", "tempTargetPresets",
            "isCommandControlEnabled", "isBolusCommandEnabled", "maxBolus", "maxCarbs", "bolusIncrement"
        ])
        #expect(reply["isCommandControlEnabled"] as? Bool == true)
        #expect(reply["isBolusCommandEnabled"] as? Bool == false)
        #expect(reply["maxBolus"] as? Double == 5)
        #expect(reply["maxCarbs"] as? Double == 120)
        // a Decimal float literal is not exact, so compare with a tolerance
        #expect(abs((reply["bolusIncrement"] as? Double ?? 0) - 0.05) < 1E-9)
        #expect(reply["req"] as? String == "presets")
        let overrides = try #require(reply["overridePresets"] as? [[String: Any]])
        #expect(overrides.first?["name"] as? String == "Sport")
        #expect(overrides.first?["isEnabled"] as? Bool == true)
        let tempTargets = try #require(reply["tempTargetPresets"] as? [[String: Any]])
        #expect(tempTargets.first?["name"] as? String == "Walk")
        #expect(outcome.refreshTrigger == nil)
    }

    @Test("Only successful preset commands push the preset list") func testPresetPushRules() async {
        let processor = SpyWatchCommandProcessor()
        let router = GarminCommandRouter(processor: processor)

        processor.result = .success(.overrideStarted, "Override started.")
        let started = await router.route(
            envelope(command: "activateOverride", payload: ["name": "Sport"]),
            from: appUUID,
            isRegistered: true,
            appName: "test"
        )
        #expect(started.pushesPresets)

        processor.result = .success(.tempTargetStopped, "Temp target stopped.")
        let stopped = await router.route(
            envelope(command: "cancelTempTarget", payload: [:]),
            from: appUUID,
            isRegistered: true,
            appName: "test"
        )
        #expect(stopped.pushesPresets)

        processor.result = .failure("Override preset not found.")
        let failed = await router.route(
            envelope(command: "activateOverride", payload: ["name": "Sport"]),
            from: appUUID,
            isRegistered: true,
            appName: "test"
        )
        #expect(failed.pushesPresets == false)

        processor.result = .success(.carbsLogged, "Carbs logged.")
        let carbs = await router.route(
            envelope(command: "carbs", payload: ["carbs": 10]),
            from: appUUID,
            isRegistered: true,
            appName: "test"
        )
        #expect(carbs.pushesPresets == false)
    }

    @Test("A preset load failure is logged by category only") func testPresetErrorSanitized() async {
        let processor = SpyWatchCommandProcessor()
        processor.presetsError = SensitiveTestError()
        let logs = LogCapture()
        var router = GarminCommandRouter(processor: processor)
        router.log = logs.record

        let outcome = await router.route(["v": 1, "req": "presets"], from: appUUID, isRegistered: true, appName: "test")

        #expect(outcome.reply == nil)
        #expect(logs.lines.contains { $0.hasPrefix("⌚️❌") && $0.contains("(unexpected)") })
        #expect(logs.lines.allSatisfy { !$0.contains(SensitiveTestError.marker) })
    }

    @Test("Invalid commands are answered only when they name a request ID") func testInvalidReplies() async {
        let processor = SpyWatchCommandProcessor()
        let router = GarminCommandRouter(processor: processor)

        let named = await router.route(
            envelope(command: "carbs", payload: ["carbs": "ten"]),
            from: appUUID,
            isRegistered: true,
            appName: "test"
        )
        #expect(named.reply?["requestId"] as? String == requestID)
        #expect(named.reply?["acknowledged"] as? Bool == false)
        #expect(named.refreshTrigger == nil)

        let anonymous = await router.route(["v": 1, "req": "command"], from: appUUID, isRegistered: true, appName: "test")
        #expect(anonymous.reply == nil)
        #expect(processor.processed.isEmpty)
    }
}

@Suite("Garmin Command Settings Migration Tests") struct GarminCommandSettingsMigrationTests {
    @Test("Settings written before commands existed decode with both switches off") func testMissingKeysDefaultOff() throws {
        let settings = try JSONDecoder().decode(TrioSettings.self, from: Data(#"{"isWatchfaceDataEnabled": true}"#.utf8))

        #expect(settings.isWatchfaceDataEnabled == true)
        #expect(settings.garminSettings.isCommandControlEnabled == false)
        #expect(settings.garminSettings.isBolusCommandEnabled == false)
    }

    @Test("Command switches survive an encode/decode round trip") func testRoundTrip() throws {
        var settings = TrioSettings()
        settings.garminSettings.isCommandControlEnabled = true
        settings.garminSettings.isBolusCommandEnabled = true

        let decoded = try JSONDecoder().decode(TrioSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded.isGarminCommandControlEnabled == true)
        #expect(decoded.isGarminBolusCommandEnabled == true)
        #expect(decoded.garminSettings == settings.garminSettings)
    }

    @Test("GarminWatchSettings without command keys keeps its other values") func testGroupedSettingsMigration() throws {
        let json =
            #"{"watchface": "swissalpine", "datafield": "swissalpine", "primaryAttributeChoice": "isf", "secondaryAttributeChoice": "eventualBG", "isWatchfaceDataEnabled": true}"#
        let settings = try JSONDecoder().decode(GarminWatchSettings.self, from: Data(json.utf8))

        #expect(settings.watchface == .swissalpine)
        #expect(settings.datafield == .swissalpine)
        #expect(settings.primaryAttributeChoice == .isf)
        #expect(settings.isWatchfaceDataEnabled == true)
        #expect(settings.isCommandControlEnabled == false)
        #expect(settings.isBolusCommandEnabled == false)
    }
}
