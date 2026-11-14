import Combine
import CoreData
import CryptoKit
import Foundation
import LoopKit
import LoopKitUI
import Swinject
import Testing

@testable import Trio

/// Captures APNs return notifications sent through `URLSession.shared`.
final class APNsCaptureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var bodies: [[String: Any]] = []

    static func reset() {
        lock.lock()
        bodies = []
        lock.unlock()
    }

    static var captured: [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return bodies
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix("push.apple.com") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 65536)
            let count = stream.read(&buffer, maxLength: buffer.count)
            stream.close()
            data = Data(buffer.prefix(max(count, 0)))
        }
        if let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            Self.lock.lock()
            Self.bodies.append(object)
            Self.lock.unlock()
        }
        if let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ProfileTestNightscoutManager: NightscoutManager {
    var notes: [String] = []
    var glucoseManager: FetchGlucoseManager?
    var cgmManager: CGMManagerUI?
    let cgmDisplayState = CurrentValueSubject<CgmDisplayState?, Never>(nil)
    let cgmProgressHighlight = CurrentValueSubject<LoopKit.DeviceLifecycleProgress?, Never>(nil)
    var cgmURL: URL? { nil }

    func fetch(_: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> { Just([]).eraseToAnyPublisher() }
    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> { Just([]).eraseToAnyPublisher() }
    func sourceInfo() -> [String: Any]? { nil }
    func fetchGlucose(since _: Date) async -> [BloodGlucose] { [] }
    func fetchCarbs() async -> [CarbsEntry] { [] }
    func fetchTempTargets() async -> [TempTarget] { [] }
    func deleteCarbs(withID _: String) async -> Bool { true }
    func deleteInsulin(withID _: String) async {}
    func deleteGlucose(withID _: String, withDate _: Date) async {}
    func uploadCarbs() async {}
    func uploadOverrides() async {}
    func uploadTempTargets() async {}
    func uploadProfiles() async throws {}
    func uploadNoteTreatment(note: String) async -> Bool {
        notes.append(note)
        return true
    }

    func uploadTherapyProfiles() async {}
    func importSettings() async -> FetchedNightscoutProfileStore? { nil }
}

private final class ProfileTestAssembly: Assembly {
    let manager: TherapyProfileManager
    let nightscout: ProfileTestNightscoutManager

    init(manager: TherapyProfileManager, nightscout: ProfileTestNightscoutManager) {
        self.manager = manager
        self.nightscout = nightscout
    }

    func assemble(container: Container) {
        container.register(TherapyProfileManager.self) { _ in self.manager }.inObjectScope(.container)
        container.register(NightscoutManager.self) { _ in self.nightscout }.inObjectScope(.container)
        container.register(TrioRemoteControl.self) { r in TrioRemoteControl(resolver: r) }.inObjectScope(.container)
    }
}

@Suite("Trio Remote Control Profile Tests", .serialized) struct TrioRemoteControlProfileTests {
    let remote: TrioRemoteControl
    let context: TherapyProfileTestContext
    var manager: TherapyProfileManager { context.manager }
    var recorder: TherapyProfileTestRecorder { context.recorder }
    let nightscout = ProfileTestNightscoutManager()
    let secret = "profile-test-secret"
    let apnsKey = P256.Signing.PrivateKey().pemRepresentation

    private let sport = TherapyProfileFixtures.profile("Sport", basal: [(0, 0.5)], sens: [(0, 70)])

    /// `TestAssembly` takes a Core Data context of its own. The remote control reads its settings from
    /// `UserDefaults.standard`, which is why the suite runs serialized.
    init() async throws {
        let coreDataStack = try await CoreDataStack.createForTests()
        let coreDataContext = coreDataStack.newTaskContext()
        context = try await TherapyProfileTestContext.make()
        let assembler = Assembler([
            StorageAssembly(),
            ServiceAssembly(),
            APSAssembly(),
            NetworkAssembly(),
            UIAssembly(),
            SecurityAssembly(),
            TestAssembly(testContext: coreDataContext),
            ProfileTestAssembly(manager: context.manager, nightscout: nightscout)
        ])
        remote = try #require(assembler.resolver.resolve(TrioRemoteControl.self))
        UserDefaults.standard.set(true, forKey: "isTrioRemoteControlEnabled")
        UserDefaults.standard.set(secret, forKey: "trioRemoteControlSharedSecret")
        URLProtocol.registerClass(APNsCaptureProtocol.self)
        APNsCaptureProtocol.reset()
        APNSJWTManager.shared.invalidateCache()
    }

    private func encrypt(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        let key = SymmetricKey(data: SHA256.hash(data: Data(secret.utf8)))
        let sealed = try AES.GCM.seal(data, using: key)
        return try #require(sealed.combined).base64EncodedString()
    }

    private func command(_ type: String, _ fields: [String: Any], timestamp: TimeInterval = Date().timeIntervalSince1970)
        -> [String: Any]
    {
        var payload: [String: Any] = [
            "user": "Tester",
            "command_type": type,
            "timestamp": timestamp,
            "command_id": UUID().uuidString,
            "return_notification": [
                "production_environment": false,
                "device_token": "abcdef",
                "bundle_id": "com.example.follow",
                "team_id": "TEAM123456",
                "key_id": "KEY1234567",
                "apns_key": apnsKey
            ]
        ]
        fields.forEach { payload[$0.key] = $0.value }
        return payload
    }

    @discardableResult private func send(_ payload: [String: Any]) async throws -> [String: Any] {
        APNsCaptureProtocol.reset()
        try await remote.handleRemoteNotification(encryptedData: try encrypt(payload))
        let ack = try #require(APNsCaptureProtocol.captured.last)
        #expect(ack["command_id"] as? String == payload["command_id"] as? String)
        #expect(ack["command_type"] as? String == payload["command_type"] as? String)
        return ack
    }

    private func body(_ ack: [String: Any]) -> String? {
        ((ack["aps"] as? [String: Any])?["alert"] as? [String: Any])?["body"] as? String
    }

    private var sportCompact: [String: Any] {
        ["units": "mg/dL", "basal": [[0, 0.5]], "carbratio": [[0, 10]], "sens": [[0, 70]], "target": [[0, 100, 110]]]
    }

    @Test("Payload decodes the profile fields") func decode() throws {
        let json = """
        {"user":"u","command_type":"save_profile","timestamp":1,"profile_name":"New","original_profile_name":"Old",
         "base_fingerprint":"0123456789abcdef","command_id":"c1",
         "profile":{"units":"mg/dL","basal":[[0,0.85]],"carbratio":[[0,10]],"sens":[[0,50]],"target":[[0,100,110]]}}
        """
        let payload = try JSONDecoder().decode(CommandPayload.self, from: Data(json.utf8))
        #expect(payload.commandType == .saveProfile)
        #expect(payload.profileName == "New")
        #expect(payload.originalProfileName == "Old")
        #expect(payload.baseFingerprint == "0123456789abcdef")
        #expect(payload.profile?.basal == [[0, 0.85]])
        #expect(payload.commandId == "c1")
        #expect(TrioRemoteControl.CommandType(rawValue: "switch_profile") == .switchProfile)
        #expect(TrioRemoteControl.CommandType(rawValue: "delete_profile") == .deleteProfile)
        #expect(TrioRemoteControl.CommandType.supported.contains(.saveProfile))
    }

    @Test("Remote save creates a profile") func remoteCreate() async throws {
        let ack = try await send(command("save_profile", ["profile_name": "Sport", "profile": sportCompact]))
        #expect(ack["command_status"] as? String == "success")
        #expect(ack["result"] as? String == "saved")
        #expect(body(ack) == "Profile 'Sport' saved")
        #expect(manager.profile(named: "Sport")?.basal.map(\.value) == [0.5])
        #expect(manager.activeProfileName == "Default")
        #expect(recorder.pumpWrites == 0)
    }

    @Test("Remote save of an existing name without original name is refused") func remoteCreateExisting() async throws {
        try await manager.save(sport, originalName: nil, baseFingerprint: nil)
        let ack = try await send(command("save_profile", ["profile_name": "Sport", "profile": sportCompact]))
        #expect(ack["command_status"] as? String == "failed")
        #expect(ack["result"] as? String == "rejected")
        #expect(body(ack)?.hasPrefix("Profile 'Sport' not saved:") == true)
        #expect(nightscout.notes.last?.contains("Profile 'Sport' not saved") == true)
    }

    @Test("Remote save with invalid values is refused, never clamped") func remoteInvalid() async throws {
        var values = sportCompact
        values["basal"] = [[0, 0]]
        let ack = try await send(command("save_profile", ["profile_name": "Zero", "profile": values]))
        #expect(ack["command_status"] as? String == "failed")
        #expect(manager.profile(named: "Zero") == nil)
        values["basal"] = [[0, 0.5]]
        values["sens"] = [[0, 600]]
        let second = try await send(command("save_profile", ["profile_name": "High", "profile": values]))
        #expect(second["command_status"] as? String == "failed")
        #expect(manager.profile(named: "High") == nil)
    }

    @Test("Remote rename and update need a matching fingerprint") func remoteRenameAndConflict() async throws {
        try await manager.save(sport, originalName: nil, baseFingerprint: nil)
        let conflict = try await send(command("save_profile", [
            "profile_name": "Sport", "original_profile_name": "Sport", "base_fingerprint": "ffffffffffffffff",
            "profile": sportCompact
        ]))
        #expect(conflict["command_status"] as? String == "failed")
        #expect(conflict["result"] as? String == "conflict")

        let missing = try await send(command("save_profile", [
            "profile_name": "Sport", "original_profile_name": "Sport", "profile": sportCompact
        ]))
        #expect(missing["command_status"] as? String == "failed")

        let fingerprint = try #require(manager.profile(named: "Sport")).fingerprint(units: .mmolL)
        let renamed = try await send(command("save_profile", [
            "profile_name": "Running", "original_profile_name": "Sport", "base_fingerprint": fingerprint,
            "profile": sportCompact
        ]))
        #expect(renamed["command_status"] as? String == "success")
        #expect(body(renamed) == "Profile 'Running' saved")
        #expect(manager.profiles().map(\.name) == ["Default", "Running"])
    }

    @Test("Remote save of the active profile writes the pump first") func remoteSaveActive() async throws {
        let base = try #require(manager.profile(named: "Default"))
        let ack = try await send(command("save_profile", [
            "profile_name": "default", "original_profile_name": "default",
            "base_fingerprint": base.fingerprint(units: .mgdL), "profile": sportCompact
        ]))
        #expect(ack["command_status"] as? String == "success")
        #expect(recorder.events.first == .pump([0.5], liveBasalAtCall: [TherapyProfileFixtures.decimal(0.85), 1]))
        #expect(context.liveBasal == [0.5])
    }

    @Test("Remote switch activates and acks") func remoteSwitch() async throws {
        try await manager.save(sport, originalName: nil, baseFingerprint: nil)
        let ack = try await send(command("switch_profile", [
            "profile_name": "Sport", "base_fingerprint": sport.fingerprint(units: .mgdL)
        ]))
        #expect(ack["command_status"] as? String == "success")
        #expect(ack["result"] as? String == "activated")
        #expect(body(ack) == "Profile 'Sport' activated")
        #expect(manager.activeProfileName == "Sport")
        #expect(context.liveBasal == [0.5])
    }

    @Test("Remote switch conflict and pump failure change nothing") func remoteSwitchFailures() async throws {
        try await manager.save(sport, originalName: nil, baseFingerprint: nil)
        let before = context.fileStorage.files
        let conflict =
            try await send(command("switch_profile", ["profile_name": "Sport", "base_fingerprint": "1111111111111111"]))
        #expect(conflict["result"] as? String == "conflict")
        let noFingerprint = try await send(command("switch_profile", ["profile_name": "Sport"]))
        #expect(noFingerprint["command_status"] as? String == "failed")

        recorder.pumpError = TherapyProfileError.noPump
        let pump = try await send(command("switch_profile", [
            "profile_name": "Sport", "base_fingerprint": sport.fingerprint(units: .mgdL)
        ]))
        #expect(pump["command_status"] as? String == "failed")
        #expect(body(pump)?.hasPrefix("Profile 'Sport' not activated:") == true)
        #expect(context.fileStorage.sameContents(as: before))
        #expect(manager.activeProfileName == "Default")

        let missing = try await send(command("switch_profile", ["profile_name": "Nope", "base_fingerprint": "1111111111111111"]))
        #expect(missing["result"] as? String == "not_found")
    }

    @Test("Remote delete refuses the active profile and deletes others") func remoteDelete() async throws {
        try await manager.save(sport, originalName: nil, baseFingerprint: nil)
        let base = try #require(manager.profile(named: "Default"))
        let active = try await send(command("delete_profile", [
            "profile_name": "default", "base_fingerprint": base.fingerprint(units: .mgdL)
        ]))
        #expect(active["command_status"] as? String == "failed")
        #expect(active["result"] as? String == "rejected")

        _ = try await manager.activate("Sport", expectedFingerprint: nil)
        let refused = try await send(command("delete_profile", [
            "profile_name": "Sport", "base_fingerprint": sport.fingerprint(units: .mgdL)
        ]))
        #expect(refused["command_status"] as? String == "failed")
        #expect(body(refused) == "Profile 'Sport' not deleted: \(TherapyProfileError.cannotDeleteActive.localizedDescription)")

        _ = try await manager.activate("Default", expectedFingerprint: nil)
        let deleted = try await send(command("delete_profile", [
            "profile_name": "Sport", "base_fingerprint": sport.fingerprint(units: .mgdL)
        ]))
        #expect(deleted["command_status"] as? String == "success")
        #expect(deleted["result"] as? String == "deleted")
        #expect(manager.profile(named: "Sport") == nil)
    }

    @Test("Remote rename of the active profile records no switch") func remoteRenameActive() async throws {
        try await manager.save(sport, originalName: nil, baseFingerprint: nil)
        _ = try await manager.activate("Sport", expectedFingerprint: nil)
        recorder.events = []
        let ack = try await send(command("save_profile", [
            "profile_name": "Running", "original_profile_name": "Sport",
            "base_fingerprint": sport.fingerprint(units: .mgdL), "profile": sportCompact
        ]))
        #expect(ack["command_status"] as? String == "success")
        #expect(body(ack) == "Profile 'Running' saved")
        #expect(manager.activeProfileName == "Running")
        #expect(recorder.events == [.profilesChanged])
    }

    @Test("A repeated command_id is rejected and not run again") func duplicateCommandId() async throws {
        let create = command("save_profile", ["profile_name": "Sport", "profile": sportCompact])
        let first = try await send(create)
        #expect(first["result"] as? String == "saved")

        try await manager.delete("Sport", expectedFingerprint: nil)
        let replay = try await send(create)
        #expect(replay["command_status"] as? String == "failed")
        #expect(replay["result"] as? String == "rejected")
        #expect(body(replay) == "Profile 'Sport' not saved: This command was already received.")
        #expect(manager.profile(named: "Sport") == nil)

        try await manager.save(sport, originalName: nil, baseFingerprint: nil)
        let activate = command("switch_profile", ["profile_name": "Sport", "base_fingerprint": sport.fingerprint(units: .mgdL)])
        #expect(try await send(activate)["result"] as? String == "activated")
        _ = try await manager.activate("Default", expectedFingerprint: nil)
        let repeated = try await send(activate)
        #expect(repeated["result"] as? String == "rejected")
        #expect(body(repeated) == "Profile 'Sport' not activated: This command was already received.")
        #expect(manager.activeProfileName == "Default")
    }

    @Test("Command ids are forgotten after the window") func replayGuardWindow() {
        let guardian = RemoteCommandReplayGuard(window: 1200)
        let start = Date()
        #expect(guardian.register("a", at: start))
        #expect(!guardian.register("a", at: start.addingTimeInterval(1199)))
        #expect(guardian.register("b", at: start.addingTimeInterval(1199)))
        #expect(guardian.register("a", at: start.addingTimeInterval(1201)))
    }

    @Test("Profile commands outside the time window are rejected") func timeWindow() async throws {
        try await manager.save(sport, originalName: nil, baseFingerprint: nil)
        let old = try await send(command(
            "switch_profile",
            ["profile_name": "Sport", "base_fingerprint": sport.fingerprint(units: .mgdL)],
            timestamp: Date().timeIntervalSince1970 - 601
        ))
        #expect(old["command_status"] as? String == "failed")
        #expect(manager.activeProfileName == "Default")
    }

    private var weekendSwitches: [[String: Any]] {
        [
            ["id": "w", "profile": "Sport", "weekday": 7, "time": 25200, "paused": true],
            ["id": "s", "profile": "default", "weekday": 2, "time": 21600]
        ]
    }

    @Test("Payload decodes the scheduled switches") func decodeScheduledSwitches() throws {
        let json = """
        {"user":"u","command_type":"save_scheduled_switches","timestamp":1,"base_fingerprint":"e3b0c44298fc1c14",
         "command_id":"c1","scheduled_switches":[{"id":"w","profile":"Weekend","weekday":7,"time":25200,"paused":true}]}
        """
        let payload = try JSONDecoder().decode(CommandPayload.self, from: Data(json.utf8))
        #expect(payload.commandType == .saveScheduledSwitches)
        #expect(payload.scheduledSwitches == [
            ScheduledProfileSwitch(id: "w", profileName: "Weekend", weekday: 7, time: 25200, paused: true)
        ])
        #expect(TrioRemoteControl.CommandType.supported.map(\.rawValue).contains("save_scheduled_switches"))
    }

    @Test("Remote save replaces the scheduled switches") func remoteSaveScheduledSwitches() async throws {
        try await manager.save(sport, originalName: nil, baseFingerprint: nil)
        let ack = try await send(command("save_scheduled_switches", [
            "scheduled_switches": weekendSwitches, "base_fingerprint": [ScheduledProfileSwitch]().fingerprint
        ]))
        #expect(ack["command_status"] as? String == "success")
        #expect(ack["result"] as? String == "saved")
        #expect(body(ack) == "Scheduled switches saved")
        #expect(manager.scheduledSwitches().map(\.profileName) == ["Default", "Sport"])
        #expect(manager.scheduledSwitches().last?.paused == true)
        #expect(recorder.pumpWrites == 0)

        let cleared = try await send(command("save_scheduled_switches", [
            "scheduled_switches": [] as [Any], "base_fingerprint": manager.scheduledSwitches().withStoreKeys.fingerprint
        ]))
        #expect(cleared["result"] as? String == "saved")
        #expect(manager.scheduledSwitches().isEmpty)
    }

    @Test("Remote save of scheduled switches needs the reviewed list and existing profiles") func remoteScheduledSwitchFailures(
    ) async throws {
        try await manager.save(sport, originalName: nil, baseFingerprint: nil)
        let missing = try await send(command("save_scheduled_switches", ["scheduled_switches": weekendSwitches]))
        #expect(missing["result"] as? String == "rejected")
        #expect(body(missing) == "Scheduled switches not saved: base_fingerprint is missing.")

        let conflict = try await send(command("save_scheduled_switches", [
            "scheduled_switches": weekendSwitches, "base_fingerprint": "1f4d16404c846d2f"
        ]))
        #expect(conflict["result"] as? String == "conflict")

        var unknown = weekendSwitches
        unknown.append(["id": "x", "profile": "Nope", "weekday": 3, "time": 0])
        let notFound = try await send(command("save_scheduled_switches", [
            "scheduled_switches": unknown, "base_fingerprint": [ScheduledProfileSwitch]().fingerprint
        ]))
        #expect(notFound["result"] as? String == "not_found")

        var clash = weekendSwitches
        clash.append(["id": "x", "profile": "Sport", "weekday": 2, "time": 21600])
        let rejected = try await send(command("save_scheduled_switches", [
            "scheduled_switches": clash, "base_fingerprint": [ScheduledProfileSwitch]().fingerprint
        ]))
        #expect(rejected["result"] as? String == "rejected")
        #expect(nightscout.notes.last?.hasPrefix("Scheduled switches not saved:") == true)
        #expect(manager.scheduledSwitches().isEmpty)

        let create = command("save_scheduled_switches", [
            "scheduled_switches": weekendSwitches, "base_fingerprint": [ScheduledProfileSwitch]().fingerprint
        ])
        #expect(try await send(create)["result"] as? String == "saved")
        let replay = try await send(create)
        #expect(replay["result"] as? String == "rejected")
        #expect(body(replay) == "Scheduled switches not saved: This command was already received.")
    }

    @Test("Remote delete removes the profile's scheduled switches and says so") func remoteDeleteWithScheduledSwitches() async throws {
        try await manager.save(sport, originalName: nil, baseFingerprint: nil)
        try await manager.saveScheduledSwitches(
            [ScheduledProfileSwitch(profileName: "Sport", weekday: 7, time: 25200)],
            baseFingerprint: nil
        )
        let ack = try await send(command("delete_profile", [
            "profile_name": "Sport", "base_fingerprint": sport.fingerprint(units: .mgdL)
        ]))
        #expect(body(ack) == "Profile 'Sport' deleted, 1 scheduled switches removed")
        #expect(manager.scheduledSwitches().isEmpty)
    }

    @Test("A remote switch is recorded as remote") func remoteSwitchTrigger() async throws {
        try await manager.save(sport, originalName: nil, baseFingerprint: nil)
        _ = try await send(command("switch_profile", [
            "profile_name": "Sport", "base_fingerprint": sport.fingerprint(units: .mgdL)
        ]))
        #expect(try context.profileStorage.profileSwitchesNotYetUploaded().map(\.trigger) == [.remote])
    }
}
