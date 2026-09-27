import Combine
import Foundation
import LoopKit
import LoopKitUI
@testable import Trio

/// Revokes from its setter the way `BaseSettingsManager` does.
final class StubSettingsManager: SettingsManager {
    let authorization = WatchCommandAuthorization()
    var settings = TrioSettings() {
        willSet { authorization.settingsWillChange(from: settings, to: newValue) }
    }

    var preferences = Preferences()
    var pumpSettings = PumpSettings(insulinActionCurve: 10, maxBolus: 10, maxBasal: 2)

    func updateInsulinCurve(_: InsulinType?) {}
}

/// Parks async calls until the test opens it, and lets the test wait until calls have arrived,
/// so suspended-operation tests do not depend on scheduling luck.
final class TestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen: Bool
    private var arrivals = 0
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var arrivalWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(isOpen: Bool = false) {
        self.isOpen = isOpen
    }

    var arrivalCount: Int { lock.withLock { arrivals } }

    func pass() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            arrivals += 1
            let reached = arrivalWaiters.filter { $0.count <= arrivals }
            arrivalWaiters.removeAll { $0.count <= arrivals }
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                parked.append(continuation)
                lock.unlock()
            }
            reached.forEach { $0.continuation.resume() }
        }
    }

    /// Counts an arrival from synchronous code without parking it.
    func arrive() {
        lock.lock()
        arrivals += 1
        let reached = arrivalWaiters.filter { $0.count <= arrivals }
        arrivalWaiters.removeAll { $0.count <= arrivals }
        lock.unlock()
        reached.forEach { $0.continuation.resume() }
    }

    func waitForArrivals(_ count: Int = 1) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if arrivals >= count {
                lock.unlock()
                continuation.resume()
            } else {
                arrivalWaiters.append((count, continuation))
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let waiting = parked
        parked = []
        lock.unlock()
        waiting.forEach { $0.resume() }
    }
}

/// A clock the test moves forward by hand, so expiry during a wait needs no real sleep.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    var now: Date { lock.withLock { date } }

    func advance(by interval: TimeInterval) {
        lock.withLock { date = date.addingTimeInterval(interval) }
    }
}

/// Polls `condition` for up to two seconds; for state that has no callback to await.
func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0 ..< 400 {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return await condition()
}

/// Counts how many validations and pump requests overlap, across concurrent requests.
final class InsulinConcurrencyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = 0
    private(set) var events: [String] = []
    private(set) var maximumInFlight = 0

    func begin(_ event: String) {
        lock.withLock {
            events.append(event)
            inFlight += 1
            maximumInFlight = max(maximumInFlight, inFlight)
        }
    }

    func end() {
        lock.withLock { inFlight -= 1 }
    }

    var recordedEvents: [String] { lock.withLock { events } }
}

final class StubBolusSafetyValidator: BolusSafetyValidator {
    private let lock = NSLock()
    private var results: [BolusSafetyResult] = []
    private var amounts: [Decimal] = []
    private var starts: [Date?] = []

    var result: BolusSafetyResult = .allowed
    /// Consumed one per call before falling back to `result`.
    var queuedResults: [BolusSafetyResult] {
        get { lock.withLock { results } }
        set { lock.withLock { results = newValue } }
    }

    var gate = TestGate(isOpen: true)
    var probe: InsulinConcurrencyProbe?
    var validatedAmounts: [Decimal] { lock.withLock { amounts } }
    var lookbackStarts: [Date?] { lock.withLock { starts } }

    func validate(bolusAmount: Decimal, lookbackStart: Date?) async throws -> BolusSafetyResult {
        probe?.begin("validate")
        defer { probe?.end() }
        lock.withLock {
            amounts.append(bolusAmount)
            starts.append(lookbackStart)
        }
        await gate.pass()
        return lock.withLock { results.isEmpty ? result : results.removeFirst() }
    }

    func fetchTotalRecentBolusAmount(since _: Date) async throws -> Decimal { 0 }
}

final class StubAdjustmentManager: AdjustmentManager {
    enum Call: Equatable {
        case activateOverride(AdjustmentRef)
        case cancelOverride
        case activateTempTarget(AdjustmentRef)
        case cancelTempTarget
    }

    private(set) var calls: [Call] = []
    private(set) var sources: [AdjustmentSource] = []
    var error: Error?
    /// Parks guarded calls before their final check, the way the adjustment serializer would.
    var gate = TestGate(isOpen: true)

    private func record(_ call: Call, source: AdjustmentSource) throws -> AdjustmentOutcome {
        calls.append(call)
        sources.append(source)
        if let error { throw error }
        return AdjustmentOutcome(started: nil, ended: [])
    }

    func activateOverride(_ preset: AdjustmentRef, source: AdjustmentSource, waitForUpload _: Bool) async throws
        -> AdjustmentOutcome
    {
        try record(.activateOverride(preset), source: source)
    }

    func cancelOverride(source: AdjustmentSource, waitForUpload _: Bool) async throws -> AdjustmentOutcome {
        try record(.cancelOverride, source: source)
    }

    func activateTempTarget(_ preset: AdjustmentRef, source: AdjustmentSource, waitForUpload _: Bool) async throws
        -> AdjustmentOutcome
    {
        try record(.activateTempTarget(preset), source: source)
    }

    func cancelTempTarget(source: AdjustmentSource, waitForUpload _: Bool) async throws -> AdjustmentOutcome {
        try record(.cancelTempTarget, source: source)
    }

    private func guarded(
        _ call: Call,
        source: AdjustmentSource,
        authorize: @Sendable() throws -> Void
    ) async throws -> AdjustmentOutcome {
        await gate.pass()
        try authorize()
        return try record(call, source: source)
    }

    func activateOverride(
        _ preset: AdjustmentRef,
        source: AdjustmentSource,
        authorize: @escaping @Sendable() throws -> Void
    ) async throws -> AdjustmentOutcome {
        try await guarded(.activateOverride(preset), source: source, authorize: authorize)
    }

    func cancelOverride(source: AdjustmentSource, authorize: @escaping @Sendable() throws -> Void) async throws
        -> AdjustmentOutcome
    {
        try await guarded(.cancelOverride, source: source, authorize: authorize)
    }

    func activateTempTarget(
        _ preset: AdjustmentRef,
        source: AdjustmentSource,
        authorize: @escaping @Sendable() throws -> Void
    ) async throws -> AdjustmentOutcome {
        try await guarded(.activateTempTarget(preset), source: source, authorize: authorize)
    }

    func cancelTempTarget(source: AdjustmentSource, authorize: @escaping @Sendable() throws -> Void) async throws
        -> AdjustmentOutcome
    {
        try await guarded(.cancelTempTarget, source: source, authorize: authorize)
    }
}

final class StubWatchCommandActions: WatchCommandActions {
    private let lock = NSLock()
    private var recordedEvents: [String] = []
    private var carbs: [(grams: Int, date: Date)] = []
    private var boluses: [Decimal] = []

    /// Side effects in call order, to check that meal carbs land before the bolus.
    var events: [String] { lock.withLock { recordedEvents } }
    var storedCarbs: [(grams: Int, date: Date)] { lock.withLock { carbs } }
    var enactedBoluses: [Decimal] { lock.withLock { boluses } }
    var carbsError: Error?
    var bolusSucceeds = true
    var overrides: [WatchPresetEntry] = []
    var tempTargets: [WatchPresetEntry] = []

    /// Parks the carb save before its final check, the way a busy Core Data context would.
    var carbsTransactionGate = TestGate(isOpen: true)
    /// Parks the carb save after it was issued, the way a slow Core Data save would.
    var carbsGate = TestGate(isOpen: true)
    /// Parks the bolus before its final check, between validation and `APSManager` issuance.
    var issueGate = TestGate(isOpen: true)
    /// Parks the bolus after it was issued, while the pump is still working on it.
    var bolusGate = TestGate(isOpen: true)
    var presetsGate = TestGate(isOpen: true)
    var probe: InsulinConcurrencyProbe?

    /// Side effects are recorded only after `authorize` passed, as in production.
    func storeCarbs(_ grams: Int, date: Date, authorize: @escaping () throws -> Void) async throws {
        await carbsTransactionGate.pass()
        try authorize()
        lock.withLock { recordedEvents.append("carbs") }
        if let carbsError { throw carbsError }
        lock.withLock { carbs.append((grams, date)) }
        await carbsGate.pass()
    }

    func enactBolus(_ units: Decimal, authorize: @escaping () throws -> Void) async throws -> Bool {
        await issueGate.pass()
        try authorize()
        probe?.begin("enact")
        defer { probe?.end() }
        lock.withLock {
            recordedEvents.append("bolus")
            boluses.append(units)
        }
        await bolusGate.pass()
        return bolusSucceeds
    }

    func overridePresets() async throws -> [WatchPresetEntry] {
        await presetsGate.pass()
        return overrides
    }

    func tempTargetPresets() async throws -> [WatchPresetEntry] {
        await presetsGate.pass()
        return tempTargets
    }
}

final class SpyWatchCommandProcessor: WatchCommandProcessor {
    var result = WatchCommandResult.success(.carbsLogged, "Carbs logged.")
    var presetsResult = WatchCommandPresets(overridePresets: [], tempTargetPresets: [])
    var presetsError: Error?
    private(set) var processed: [WatchCommandRequest] = []
    private(set) var presetRequests = 0

    func process(_ request: WatchCommandRequest) async -> WatchCommandResult {
        processed.append(request)
        return result
    }

    func presets() async throws -> WatchCommandPresets {
        presetRequests += 1
        if let presetsError { throw presetsError }
        return presetsResult
    }
}

/// Error whose every description carries a marker that must never reach a log or an ack.
struct SensitiveTestError: LocalizedError, CustomStringConvertible {
    static let marker = "SENSITIVE-7f3a"

    var description: String { "carbs=42g bolus=3.5U \(Self.marker)" }
    var errorDescription: String? { description }
}

/// Collects log lines from the injectable log sinks.
final class LogCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var lines: [String] { lock.withLock { storage } }

    func record(_ line: String) {
        lock.withLock { storage.append(line) }
    }
}

/// Records bolus requests; everything else is inert. `enactBolus` calls back like the real one.
final class SpyAPSManager: APSManager, @unchecked Sendable {
    private let lock = NSLock()
    private var amounts: [Double] = []

    var bolusRequests: [Double] { lock.withLock { amounts } }
    var bolusSucceeds = true

    func enactBolus(amount: Double, isSMB _: Bool, callback: ((Bool, String) -> Void)?) async {
        lock.withLock { amounts.append(amount) }
        callback?(bolusSucceeds, "")
    }

    func heartbeat(date _: Date) {}
    func markNextLoopUserInitiated() {}
    func enactManualTempBasal(rate _: Double, duration _: TimeInterval) async {}
    var pumpManager: PumpManagerUI?
    var bluetoothManager: BluetoothStateManager? { nil }
    let pumpDisplayState = CurrentValueSubject<PumpDisplayState?, Never>(nil)
    let pumpName = CurrentValueSubject<String, Never>("")
    let isLooping = CurrentValueSubject<Bool, Never>(false)
    var lastLoopDate: Date { .distantPast }
    let lastLoopDateSubject = PassthroughSubject<Date, Never>()
    let bolusProgress = CurrentValueSubject<Decimal?, Never>(nil)
    let pumpExpiresAtDate = CurrentValueSubject<Date?, Never>(nil)
    let pumpActivatedAtDate = CurrentValueSubject<Date?, Never>(nil)
    var isManualTempBasal: Bool { false }
    var isScheduledBasal: Bool? { nil }
    var isSuspended: Bool { false }
    func determineBasal() async throws {}
    func determineBasalSync() async throws {}
    func simulateDetermineBasal(
        simulatedCarbsAmount _: Decimal,
        simulatedBolusAmount _: Decimal,
        simulatedCarbsDate _: Date?
    ) async -> Determination? { nil }
    func roundBolus(amount: Decimal) -> Decimal { amount }
    let lastError = CurrentValueSubject<Error?, Never>(nil)
    func cancelBolus(_: ((Bool, String) -> Void)?) async {}
    let iobFileDidUpdate = PassthroughSubject<Void, Never>()
}
