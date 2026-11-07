import CoreData
import Foundation
import Swinject
import Testing
@testable import Trio

/// FileStorage kept in memory, encoded with the app's JSON coding.
final class InMemoryFileStorage: FileStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var contents: [String: Data] = [:]
    /// Saves to these files are dropped.
    var failingWrites: Set<String> = []

    var files: [String: Data] { lock.withLock { contents } }

    func save<Value: JSON>(_ value: Value, as name: String) {
        guard !failingWrites.contains(name) else { return }
        let data = (value as? RawJSON).map { Data($0.utf8) } ?? (try? JSONCoding.encoder.encode(value))
        lock.withLock { contents[name] = data }
    }

    func saveAsync<Value: JSON>(_ value: Value, as name: String) async { save(value, as: name) }

    func retrieve<Value: JSON>(_ name: String, as type: Value.Type) -> Value? {
        lock.withLock { contents[name] }.flatMap { try? JSONCoding.decoder.decode(type, from: $0) }
    }

    func retrieveAsync<Value: JSON>(_ name: String, as type: Value.Type) async -> Value? { retrieve(name, as: type) }

    func retrieveRaw(_ name: String) -> RawJSON? {
        lock.withLock { contents[name] }.flatMap { String(data: $0, encoding: .utf8) }
    }

    func retrieveRawAsync(_ name: String) async -> RawJSON? { retrieveRaw(name) }
    func append<Value: JSON>(_: Value, to _: String) {}
    func append<Value: JSON>(_: [Value], to _: String) {}
    func append<Value: JSON, T: Equatable>(_: Value, to _: String, uniqBy _: KeyPath<Value, T>) {}
    func append<Value: JSON, T: Equatable>(_: [Value], to _: String, uniqBy _: KeyPath<Value, T>) {}
    func remove(_ name: String) { lock.withLock { contents[name] = nil } }

    func rename(_ name: String, to newName: String) {
        lock.withLock {
            contents[newName] = contents[name]
            contents[name] = nil
        }
    }

    func transaction(_ exec: (FileStorage) -> Void) { exec(self) }
    func urlFor(file _: String) -> URL? { nil }

    /// Compares decoded JSON, since the encoder's key order is not stable.
    func sameContents(as other: [String: Data]) -> Bool {
        func object(_ data: Data?) -> NSObject? {
            data.flatMap { try? JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed]) as? NSObject }
        }
        let files = files
        return Set(files.keys) == Set(other.keys) && files.keys.allSatisfy { object(files[$0]) == object(other[$0]) }
    }
}

/// Core Data profile storage whose saves can be made to fail.
final class FailableTherapyProfileStorage: TherapyProfileStorage, @unchecked Sendable {
    private let base: TherapyProfileStorage
    var failsToStore = false
    /// Runs before every store; a throw stops the store.
    var beforeStore: (() throws -> Void)?

    init(base: TherapyProfileStorage) {
        self.base = base
    }

    func fetchProfiles() throws -> StoredTherapyProfiles {
        try base.fetchProfiles()
    }

    func storeProfiles(_ profiles: StoredTherapyProfiles) async throws {
        if failsToStore { throw TherapyProfileError.storageFailed }
        try beforeStore?()
        try await base.storeProfiles(profiles)
    }

    func settleScheduledSwitches(at date: Date) async throws {
        try await base.settleScheduledSwitches(at: date)
    }
}

/// Records pump writes, determinations and notifications, in order.
final class TherapyProfileTestRecorder: Broadcaster, BasalProfileObserver, TherapyProfilesObserver, @unchecked Sendable {
    enum Event: Equatable {
        case pump([Decimal], liveBasalAtCall: [Decimal])
        case liveChanged
        case profilesChanged
        case recompute
    }

    private let lock = NSLock()
    private var recorded: [Event] = []
    var events: [Event] {
        get { lock.withLock { recorded } }
        set { lock.withLock { recorded = newValue } }
    }

    var basalLimits = TherapyBasalLimits(
        supportedRates: (1 ... 600).map { Decimal($0) * 5 / 100 },
        maxBasal: 3
    )
    var now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Scheduled switches in tests run in this zone.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }()

    var pumpError: Error?
    var pumpSuspended = false
    var bolusInProgress = false
    let alerts = SpyAlertManager()
    /// Results of the next pump writes, in order, before `pumpError` applies.
    var pumpResults: [Error?] = []
    var liveBasal: () -> [Decimal] = { [] }
    /// Awaited inside every pump write, to hold an operation in flight.
    var pumpGate: (() async -> Void)?

    var pumpWrites: Int { events.filter { if case .pump = $0 { return true } else { return false } }.count }

    func syncBasalSchedule(_ entries: [BasalProfileEntry]) async throws {
        append(.pump(entries.map(\.rate), liveBasalAtCall: liveBasal()))
        await pumpGate?()
        let result = lock.withLock { pumpResults.isEmpty ? pumpError : pumpResults.removeFirst() }
        if let result { throw result }
    }

    func recompute() async { append(.recompute) }

    private func append(_ event: Event) { lock.withLock { recorded.append(event) } }

    // Delivers to this recorder only, so suites running in parallel do not see each other.
    func register<T>(_: T.Type, observer _: T) {}
    func unregister<T>(_: T.Type, observer _: T) {}
    func unregister<T>(_: T.Type) {}
    func notify<T>(_: T.Type, on _: DispatchQueue, block: @escaping (T) -> Void) {
        if let observer = self as? T { block(observer) }
    }

    func basalProfileDidChange(_: [BasalProfileEntry]) { append(.liveChanged) }
    func therapyProfilesDidChange() { append(.profilesChanged) }
}

final class TherapyProfileTestAssembly: Assembly {
    let fileStorage: InMemoryFileStorage
    let profileStorage: FailableTherapyProfileStorage
    let recorder: TherapyProfileTestRecorder

    init(fileStorage: InMemoryFileStorage, profileStorage: FailableTherapyProfileStorage, recorder: TherapyProfileTestRecorder) {
        self.fileStorage = fileStorage
        self.profileStorage = profileStorage
        self.recorder = recorder
    }

    func assemble(container: Container) {
        container.register(FileStorage.self) { _ in self.fileStorage }.inObjectScope(.container)
        container.register(Broadcaster.self) { _ in self.recorder }.inObjectScope(.container)
        container.register(TherapyProfileStorage.self) { _ in self.profileStorage }.inObjectScope(.container)
        container.register(TrioAlertManager.self) { _ in self.recorder.alerts }.inObjectScope(.container)
        container.register(TherapyProfileManager.self) { r in
            let recorder = self.recorder
            return BaseTherapyProfileManager(
                resolver: r,
                syncBasalSchedule: { try await recorder.syncBasalSchedule($0) },
                basalLimits: { recorder.basalLimits },
                pumpSuspended: { recorder.pumpSuspended },
                bolusInProgress: { recorder.bolusInProgress },
                recompute: { await recorder.recompute() },
                now: { recorder.now },
                calendar: TherapyProfileTestRecorder.calendar
            )
        }.inObjectScope(.container)
    }
}

struct TherapyProfileTestContext {
    let coreDataStack: CoreDataStack
    let manager: TherapyProfileManager
    let fileStorage: InMemoryFileStorage
    let profileStorage: FailableTherapyProfileStorage
    let recorder: TherapyProfileTestRecorder
    let resolver: Resolver

    var liveBasal: [Decimal] {
        fileStorage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)?.map(\.rate) ?? []
    }

    static func make(
        live: TrioTherapyProfile = TherapyProfileFixtures
            .profile("Default")
    ) async throws -> TherapyProfileTestContext {
        let fileStorage = InMemoryFileStorage()
        fileStorage.save(live.basalProfileEntries, as: OpenAPS.Settings.basalProfile)
        fileStorage.save(live.carbRatios, as: OpenAPS.Settings.carbRatios)
        fileStorage.save(live.insulinSensitivities, as: OpenAPS.Settings.insulinSensitivities)
        fileStorage.save(live.bgTargets, as: OpenAPS.Settings.bgTargets)
        return try make(coreDataStack: try await CoreDataStack.createForTests(), fileStorage: fileStorage)
    }

    /// A new manager over the same Core Data store and settings files, as after an app restart.
    func relaunched() throws -> TherapyProfileTestContext {
        try Self.make(coreDataStack: coreDataStack, fileStorage: fileStorage)
    }

    private static func make(coreDataStack: CoreDataStack, fileStorage: InMemoryFileStorage) throws -> TherapyProfileTestContext {
        let profileStorage = FailableTherapyProfileStorage(
            base: BaseTherapyProfileStorage(contextProvider: { coreDataStack.newTaskContext() })
        )
        let recorder = TherapyProfileTestRecorder()
        recorder.liveBasal = {
            fileStorage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)?.map(\.rate) ?? []
        }
        let resolver = Assembler([
            StorageAssembly(),
            ServiceAssembly(),
            APSAssembly(),
            NetworkAssembly(),
            UIAssembly(),
            SecurityAssembly(),
            TestAssembly(testContext: coreDataStack.newTaskContext()),
            TherapyProfileTestAssembly(fileStorage: fileStorage, profileStorage: profileStorage, recorder: recorder)
        ]).resolver
        return TherapyProfileTestContext(
            coreDataStack: coreDataStack,
            manager: try #require(resolver.resolve(TherapyProfileManager.self)),
            fileStorage: fileStorage,
            profileStorage: profileStorage,
            recorder: recorder,
            resolver: resolver
        )
    }
}

/// Suspends callers of `wait()` until `open()`.
actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}

struct PumpFailure: Error, LocalizedError {
    var errorDescription: String? { "pump unreachable" }
}
