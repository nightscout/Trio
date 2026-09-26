import Combine
import ConnectIQ
import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

/// A task context whose saves fail the way a full disk or a validation error would.
final class FailingSaveContext: NSManagedObjectContext {
    override func save() throws {
        throw NSError(
            domain: NSCocoaErrorDomain,
            code: NSValidationMultipleErrorsError,
            userInfo: [NSLocalizedDescriptionKey: "carbs=40 \(SensitiveTestError.marker)"]
        )
    }
}

/// Overrides the storage and safety services the production watch actions use.
private final class WatchCommandOverrideAssembly: Assembly {
    private let carbsContext: () -> NSManagedObjectContext
    private let validator: BolusSafetyValidator
    private let processor: WatchCommandProcessor?

    init(
        carbsContext: @escaping () -> NSManagedObjectContext,
        validator: BolusSafetyValidator,
        processor: WatchCommandProcessor? = nil
    ) {
        self.carbsContext = carbsContext
        self.validator = validator
        self.processor = processor
    }

    func assemble(container: Container) {
        container.register(CarbsStorage.self) { [carbsContext] r in
            BaseCarbsStorage(resolver: r, contextProvider: carbsContext)
        }.inObjectScope(.container)
        container.register(BolusSafetyValidator.self) { [validator] _ in validator }
        if let processor {
            container.register(WatchCommandProcessor.self) { _ in processor }.inObjectScope(.container)
        }
    }
}

private func makeResolver(
    stack: CoreDataStack,
    carbsContext: @escaping () -> NSManagedObjectContext,
    validator: BolusSafetyValidator = StubBolusSafetyValidator(),
    processor: WatchCommandProcessor? = nil
) -> Resolver {
    Assembler([
        StorageAssembly(),
        ServiceAssembly(),
        APSAssembly(),
        NetworkAssembly(),
        UIAssembly(),
        SecurityAssembly(),
        TestAssembly(testContext: stack.newTaskContext()),
        WatchCommandOverrideAssembly(carbsContext: carbsContext, validator: validator, processor: processor)
    ]).resolver
}

// MARK: - Carb Persistence

@Suite("Watch Command Carb Persistence Tests", .serialized) struct WatchCommandCarbPersistenceTests {
    let stack: CoreDataStack
    let failingContext: FailingSaveContext

    init() async throws {
        stack = try await CoreDataStack.createForTests()
        failingContext = FailingSaveContext(concurrencyType: .privateQueueConcurrencyType)
        failingContext.persistentStoreCoordinator = stack.persistentContainer.persistentStoreCoordinator
    }

    private func storedCarbRows() async throws -> Int {
        let context = stack.newTaskContext()
        return try await context.perform {
            try context.count(for: NSFetchRequest<CarbEntryStored>(entityName: "CarbEntryStored"))
        }
    }

    @Test("A failed save throws from the verified path but stays silent for existing callers") func testStorageBoundary(
    ) async throws {
        let context = failingContext
        let resolver = makeResolver(stack: stack, carbsContext: { context })
        let storage = try #require(resolver.resolve(CarbsStorage.self))

        await #expect(throws: NSError.self) {
            try await storage.storeVerifiedCarbs(storage.makeCarbEntry(carbs: 40, date: Date()))
        }
        // unchanged contract for the app's own callers
        try await storage.storeCarbs([storage.makeCarbEntry(carbs: 40, date: Date())], areFetchedFromRemote: false)
        #expect(try await storedCarbRows() == 0)
    }

    @Test("A successful verified save persists the carb row") func testStorageSuccess() async throws {
        let stack = self.stack
        let resolver = makeResolver(stack: stack, carbsContext: { stack.newTaskContext() })
        let storage = try #require(resolver.resolve(CarbsStorage.self))

        try await storage.storeVerifiedCarbs(storage.makeCarbEntry(carbs: 25, date: Date()))

        #expect(try await storedCarbRows() == 1)
    }

    @Test("A real carb save failure never acks carbs or reaches the bolus") func testProductionActionFailure() async throws {
        let context = failingContext
        let validator = StubBolusSafetyValidator()
        let resolver = makeResolver(stack: stack, carbsContext: { context }, validator: validator)
        let settings = try #require(resolver.resolve(SettingsManager.self))
        settings.settings.isGarminCommandControlEnabled = true
        settings.settings.isGarminBolusCommandEnabled = true

        let logs = LogCapture()
        let processor = BaseWatchCommandProcessor(
            resolver: resolver,
            actions: BaseWatchCommandActions(resolver: resolver),
            log: logs.record
        )
        let appUUID = UUID()

        let carbs = await processor.process(
            WatchCommandRequest(requestID: UUID(), appUUID: appUUID, date: Date(), command: .carbs(40))
        )
        let meal = await processor.process(
            WatchCommandRequest(requestID: UUID(), appUUID: appUUID, date: Date(), command: .mealBolus(carbs: 40, bolus: 2))
        )

        #expect(carbs.acknowledged == false)
        #expect(carbs.ackCode == .genericFailure)
        #expect(meal.acknowledged == false)
        #expect(meal.ackCode == .genericFailure, "No partial failure: nothing was logged")
        #expect(validator.validatedAmounts.isEmpty, "The bolus stage is never reached")
        #expect(try await storedCarbRows() == 0)
        #expect(logs.lines.contains { $0.contains("(cocoa(\(NSValidationMultipleErrorsError)))") })
        #expect(logs.lines.allSatisfy { !$0.contains(SensitiveTestError.marker) })
    }
}

// MARK: - Garmin Manager

final class InstalledAppStatus: IQAppStatus {
    override var isInstalled: Bool { true }
}

/// Stands in for the Connect IQ SDK and records every message with the exact app it targeted.
final class SpyConnectIQClient: GarminConnectIQClient, @unchecked Sendable {
    struct Sent {
        let message: Any
        let appUUID: UUID
        let deviceUUID: UUID

        var request: String? { (message as? [String: Any])?[WatchMessageKeys.request] as? String }
    }

    private let lock = NSLock()
    private var messages: [Sent] = []
    /// Remaining failures per app UUID + device UUID, to exercise the retry.
    private var failures: [String: Int] = [:]

    var sent: [Sent] { lock.withLock { messages } }

    func failNextSend(to appUUID: UUID, on deviceUUID: UUID) {
        lock.withLock { failures["\(appUUID)-\(deviceUUID)", default: 0] += 1 }
    }

    func registerDevice(_: IQDevice, delegate _: IQDeviceEventDelegate) {}

    func registerApp(_: IQApp, delegate _: IQAppMessageDelegate) {}

    func appStatus(of _: IQApp, completion: @escaping (IQAppStatus?) -> Void) {
        completion(InstalledAppStatus())
    }

    func send(_ message: Any, to app: IQApp, completion: @escaping (IQSendMessageResult) -> Void) {
        let target = "\(app.uuid!)-\(app.device.uuid!)"
        let fails: Bool = lock.withLock {
            messages.append(Sent(message: message, appUUID: app.uuid, deviceUUID: app.device.uuid))
            guard let remaining = failures[target], remaining > 0 else { return false }
            failures[target] = remaining - 1
            return true
        }
        // raw value 1 is IQSendMessageResult_Failure_Unknown
        completion(fails ? IQSendMessageResult(rawValue: 1)! : .success)
    }
}

@Suite("Garmin Manager Command Integration Tests", .serialized) final class GarminManagerCommandIntegrationTests {
    let complicationUUID = GarminWatchface.complication.watchfaceUUID!
    let datafieldUUID = GarminDatafield.swissalpine.datafieldUUID!
    let deviceA = IQDevice(id: UUID(), modelName: "fenix 8", friendlyName: "A")!
    let deviceB = IQDevice(id: UUID(), modelName: "Enduro 3", friendlyName: "B")!

    let processor: SpyWatchCommandProcessor
    let client: SpyConnectIQClient
    let presetChanges: PassthroughSubject<Void, Never>
    let settings: SettingsManager
    let manager: BaseGarminManager

    init() async throws {
        let stack = try await CoreDataStack.createForTests()
        let processor = SpyWatchCommandProcessor()
        let client = SpyConnectIQClient()
        let presetChanges = PassthroughSubject<Void, Never>()
        let resolver = makeResolver(stack: stack, carbsContext: { stack.newTaskContext() }, processor: processor)

        let settings = try #require(resolver.resolve(SettingsManager.self))
        settings.settings.garminSettings.watchface = .complication
        settings.settings.garminSettings.isWatchfaceDataEnabled = true
        settings.settings.garminSettings.datafield = .swissalpine
        settings.settings.garminSettings.isCommandControlEnabled = true

        self.processor = processor
        self.client = client
        self.presetChanges = presetChanges
        self.settings = settings
        manager = BaseGarminManager(
            resolver: resolver,
            connectIQClient: client,
            presetChanges: presetChanges.eraseToAnyPublisher(),
            sendRetryDelay: 0.01
        )
        manager.updateDeviceList([deviceA, deviceB])
    }

    deinit {
        // the device list is persisted in user defaults
        manager.updateDeviceList([])
    }

    private func app(_ uuid: UUID, on device: IQDevice) -> IQApp {
        IQApp(uuid: uuid, store: UUID(), device: device)
    }

    private func command(_ name: String, payload: [String: Any], requestID: String) -> [String: Any] {
        [
            "v": 1,
            "req": "command",
            "requestId": requestID,
            "date": NSNumber(value: UInt64(Date().timeIntervalSince1970 * 1000)),
            "command": name,
            "payload": payload
        ]
    }

    private func sent(_ request: String) -> [SpyConnectIQClient.Sent] {
        client.sent.filter { $0.request == request }
    }

    @Test("An ack goes only to the app and device that sent the command") func testAckTargetsOriginatingApp() async {
        let requestID = UUID().uuidString
        manager.receivedMessage(
            command("carbs", payload: ["carbs": 20], requestID: requestID),
            from: app(complicationUUID, on: deviceB)
        )

        #expect(await eventually { !self.sent("ack").isEmpty })
        let acks = sent("ack")
        #expect(acks.count == 1)
        #expect(acks.allSatisfy { $0.appUUID == complicationUUID && $0.deviceUUID == deviceB.uuid })
        #expect(acks.first.flatMap { ($0.message as? [String: Any])?["requestId"] as? String } == requestID)
        #expect(processor.processed.map(\.appUUID) == [complicationUUID])
        #expect(client.sent.allSatisfy { $0.appUUID != datafieldUUID }, "Nothing command-related is fanned out")
    }

    @Test("A preset request is answered only to the requesting app") func testPresetsReplyTargeted() async {
        processor.presetsResult = WatchCommandPresets(
            overridePresets: [OverridePresetWatch(name: "Sport", isEnabled: false)],
            tempTargetPresets: []
        )
        manager.receivedMessage(["v": 1, "req": "presets"], from: app(complicationUUID, on: deviceA))

        #expect(await eventually { !self.sent("presets").isEmpty })
        let replies = sent("presets")
        #expect(replies.count == 1)
        #expect(replies.first?.appUUID == complicationUUID)
        #expect(replies.first?.deviceUUID == deviceA.uuid)
    }

    @Test("A failed ack is resent to the same app") func testAckRetryTarget() async {
        client.failNextSend(to: complicationUUID, on: deviceA.uuid)
        let requestID = UUID().uuidString
        manager.receivedMessage(
            command("carbs", payload: ["carbs": 20], requestID: requestID),
            from: app(complicationUUID, on: deviceA)
        )

        #expect(await eventually { self.sent("ack").count == 2 })
        let acks = sent("ack")
        #expect(acks.allSatisfy { $0.appUUID == complicationUUID && $0.deviceUUID == deviceA.uuid })
        #expect(acks.allSatisfy { ($0.message as? [String: Any])?["requestId"] as? String == requestID })
    }

    @Test("A started preset pushes the list to every Complication app, never to datafields") func testCommandPushesPresets() async {
        processor.result = .success(.overrideStarted, "Override started.")
        manager.receivedMessage(
            command("activateOverride", payload: ["name": "Sport"], requestID: UUID().uuidString),
            from: app(complicationUUID, on: deviceA)
        )

        #expect(await eventually { self.sent("presets").count == 2 })
        let pushes = sent("presets")
        #expect(Set(pushes.map(\.deviceUUID)) == [deviceA.uuid, deviceB.uuid])
        #expect(pushes.allSatisfy { $0.appUUID == complicationUUID })
        #expect(sent("ack").map(\.deviceUUID) == [deviceA.uuid])
        #expect(client.sent.allSatisfy { $0.appUUID != datafieldUUID })
    }

    @Test("Preset storage changes push to Complication apps only") func testStorageChangePushesPresets() async {
        presetChanges.send(())

        #expect(await eventually { self.sent("presets").count == 2 })
        #expect(sent("presets").allSatisfy { $0.appUUID == complicationUUID })
        #expect(Set(sent("presets").map(\.deviceUUID)) == [deviceA.uuid, deviceB.uuid])
        #expect(processor.processed.isEmpty)
    }

    @Test("A message from an unregistered device is ignored") func testUnregisteredDevice() async throws {
        let stranger = try #require(IQDevice(id: UUID(), modelName: "fenix 8", friendlyName: "C"))
        manager.receivedMessage(
            command("carbs", payload: ["carbs": 20], requestID: UUID().uuidString),
            from: app(complicationUUID, on: stranger)
        )

        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(client.sent.isEmpty)
        #expect(processor.processed.isEmpty)
    }

    @Test("Changing either command setting revokes pending commands") func testSettingsRevoke() async {
        settings.settings.garminSettings.isCommandControlEnabled = false
        #expect(await eventually { self.processor.revocations == 1 })

        settings.settings.garminSettings.isBolusCommandEnabled = true
        #expect(await eventually { self.processor.revocations == 2 })

        settings.settings.garminSettings.primaryAttributeChoice = .isf
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(processor.revocations == 2, "Display settings leave commands alone")
    }
}
