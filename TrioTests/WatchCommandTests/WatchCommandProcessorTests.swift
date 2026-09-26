import Foundation
import Swinject
import Testing

@testable import Trio

/// Covers what the processor decides before and around the side effects: freshness, gates,
/// limits, deduplication and the meal sequencing. Pump, Core Data and presets are stubbed.
@Suite("Watch Command Processor Tests") struct WatchCommandProcessorTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
    let appUUID = UUID()

    let settings = StubSettingsManager()
    let validator = StubBolusSafetyValidator()
    let adjustments = StubAdjustmentManager()
    let actions = StubWatchCommandActions()
    let cache = WatchCommandRequestCache()
    let logs = LogCapture()
    let container = Container()
    let processor: BaseWatchCommandProcessor

    init() {
        settings.settings.isGarminCommandControlEnabled = true
        settings.settings.isGarminBolusCommandEnabled = true
        settings.settings.maxCarbs = 100

        container.register(SettingsManager.self) { [settings] _ in settings }
        container.register(BolusSafetyValidator.self) { [validator] _ in validator }
        container.register(AdjustmentManager.self) { [adjustments] _ in adjustments }
        container.register(WatchCommandAuthorization.self) { [settings] _ in settings.authorization }

        processor = Self.makeProcessor(container: container, actions: actions, cache: cache, clock: clock, logs: logs)
    }

    private static func makeProcessor(
        container: Container,
        actions: WatchCommandActions,
        cache: WatchCommandRequestCache = WatchCommandRequestCache(),
        insulinLane: WatchCommandInsulinLane = WatchCommandInsulinLane(),
        clock: TestClock,
        logs: LogCapture
    ) -> BaseWatchCommandProcessor {
        BaseWatchCommandProcessor(
            resolver: container,
            actions: actions,
            cache: cache,
            insulinLane: insulinLane,
            now: { clock.now },
            log: logs.record
        )
    }

    private func request(
        _ command: WatchCommand,
        id: UUID = UUID(),
        app: UUID? = nil,
        age: TimeInterval = 5
    ) -> WatchCommandRequest {
        WatchCommandRequest(requestID: id, appUUID: app ?? appUUID, date: now.addingTimeInterval(-age), command: command)
    }

    // MARK: - Registration

    @Test("Processor is registered once for the whole app") func testContainerScoped() {
        let resolver = TrioApp().resolver
        let first = resolver.resolve(WatchCommandProcessor.self)
        let second = resolver.resolve(WatchCommandProcessor.self)
        #expect(first is BaseWatchCommandProcessor)
        #expect(first as AnyObject? === second as AnyObject?, "One instance means one request-ID cache")
    }

    // MARK: - Freshness

    @Test(
        "Timestamps are accepted from 10 minutes old to 60 seconds ahead",
        arguments: [
            (TimeInterval(600), true),
            (TimeInterval(600.001), false),
            (TimeInterval(-60), true),
            (TimeInterval(-60.001), false),
            (TimeInterval(0), true)
        ]
    ) func testFreshnessWindow(age: TimeInterval, accepted: Bool) async {
        let result = await processor.process(request(.carbs(10), age: age))

        #expect(result.acknowledged == accepted)
        #expect(actions.storedCarbs.count == (accepted ? 1 : 0))
    }

    // MARK: - Gates

    @Test("Master switch off rejects every mutable command without side effects") func testMasterSwitchOff() async {
        settings.settings.isGarminCommandControlEnabled = false

        let commands: [WatchCommand] = [
            .carbs(10), .bolus(1), .mealBolus(carbs: 10, bolus: 1),
            .activateOverride(name: "Sport"), .cancelOverride,
            .activateTempTarget(name: "Walk"), .cancelTempTarget
        ]
        for command in commands {
            let result = await processor.process(request(command))
            #expect(result.acknowledged == false)
            #expect(result.ackCode == .genericFailure)
        }

        #expect(actions.events.isEmpty)
        #expect(adjustments.calls.isEmpty)
        #expect(validator.validatedAmounts.isEmpty)
    }

    @Test("Bolus switch off rejects bolus and meal bolus but not carbs") func testBolusSwitchOff() async {
        settings.settings.isGarminBolusCommandEnabled = false

        #expect(await processor.process(request(.bolus(1))).acknowledged == false)
        #expect(await processor.process(request(.mealBolus(carbs: 20, bolus: 1))).acknowledged == false)
        #expect(actions.events.isEmpty, "A rejected meal bolus must not log its carbs either")

        #expect(await processor.process(request(.carbs(20))).acknowledged == true)
    }

    // MARK: - Carbs

    @Test("Carbs are stored with the command date") func testCarbs() async {
        let request = request(.carbs(30), age: 90)
        let result = await processor.process(request)

        #expect(result == .success(.carbsLogged, result.message))
        #expect(actions.storedCarbs.map(\.grams) == [30])
        #expect(actions.storedCarbs.first?.date == request.date)
        #expect(result.refreshesState)
    }

    @Test("Carbs above max carbs are rejected; exactly max carbs is allowed") func testMaxCarbs() async {
        settings.settings.maxCarbs = 50

        #expect(await processor.process(request(.carbs(51))).acknowledged == false)
        #expect(await processor.process(request(.mealBolus(carbs: 51, bolus: 1))).acknowledged == false)
        #expect(actions.events.isEmpty)

        #expect(await processor.process(request(.carbs(50))).acknowledged == true)
    }

    @Test("Non-positive amounts are rejected") func testNonPositiveAmounts() async {
        #expect(await processor.process(request(.carbs(0))).acknowledged == false)
        #expect(await processor.process(request(.carbs(-5))).acknowledged == false)
        #expect(await processor.process(request(.bolus(0))).acknowledged == false)
        #expect(actions.events.isEmpty)
        #expect(validator.validatedAmounts.isEmpty)
    }

    @Test("A failed carb save is a failure") func testCarbsStoreFailure() async {
        actions.carbsError = TestError("save failed")
        let result = await processor.process(request(.carbs(10)))

        #expect(result.acknowledged == false)
        #expect(result.ackCode == .genericFailure)
    }

    // MARK: - Bolus

    @Test("An allowed bolus is enacted") func testBolusAllowed() async {
        let result = await processor.process(request(.bolus(1.5)))

        #expect(result.acknowledged)
        #expect(result.ackCode == .genericSuccess)
        #expect(validator.validatedAmounts == [1.5])
        #expect(actions.enactedBoluses == [1.5])
    }

    @Test(
        "Every safety rejection stops the bolus",
        arguments: [
            BolusSafetyRejection.exceedsMaxBolus(maxBolus: 5),
            .iobUnavailable,
            .exceedsMaxIOB(currentIOB: 4, maxIOB: 5),
            .recentBolusWithinWindow(totalRecent: 1)
        ]
    ) func testBolusSafetyRejections(reason: BolusSafetyRejection) async {
        validator.result = .rejected(reason)
        let result = await processor.process(request(.bolus(2)))

        #expect(result.acknowledged == false)
        #expect(result.ackCode == .genericFailure)
        #expect(actions.enactedBoluses.isEmpty)
        #expect(!result.message.contains("2"), "Acks never carry treatment amounts")
    }

    @Test("A pump failure is reported as a failure") func testBolusPumpFailure() async {
        actions.bolusSucceeds = false
        let result = await processor.process(request(.bolus(1)))

        #expect(result.acknowledged == false)
        #expect(result.ackCode == .genericFailure)
    }

    @Test("Recent-bolus lookback covers the standard window and everything since the command") func testLookbackStart() async {
        let standardWindowStart = now.addingTimeInterval(-Double(BolusSafetyEvaluator.recentBolusWindowMinutes * 60))

        // separate processors: a second bolus through one lane is stopped before validation
        _ = await processor.process(request(.bolus(1), age: 60))
        let second = Self.makeProcessor(container: container, actions: StubWatchCommandActions(), clock: clock, logs: logs)
        _ = await second.process(request(.bolus(1), age: 9 * 60))

        #expect(validator.lookbackStarts == [standardWindowStart, now.addingTimeInterval(-9 * 60)])
    }

    // MARK: - Meal Bolus

    @Test("Meal bolus logs carbs before enacting the bolus") func testMealBolusOrder() async {
        let result = await processor.process(request(.mealBolus(carbs: 40, bolus: 3)))

        #expect(result.acknowledged)
        #expect(result.ackCode == .genericSuccess)
        #expect(actions.events == ["carbs", "bolus"])
        #expect(actions.storedCarbs.map(\.grams) == [40])
        #expect(actions.enactedBoluses == [3])
    }

    @Test("A rejected meal bolus keeps the carbs and reports a partial failure") func testMealBolusPartialFailure() async {
        validator.result = .rejected(.exceedsMaxIOB(currentIOB: 4, maxIOB: 5))
        let result = await processor.process(request(.mealBolus(carbs: 40, bolus: 3)))

        #expect(result.acknowledged == false)
        #expect(result.ackCode == .partialFailure)
        #expect(result.refreshesState, "Carbs changed, so the watch needs fresh state")
        #expect(actions.storedCarbs.map(\.grams) == [40])
        #expect(actions.enactedBoluses.isEmpty)
    }

    @Test("A pump failure after meal carbs is a partial failure") func testMealBolusPumpFailure() async {
        actions.bolusSucceeds = false
        let result = await processor.process(request(.mealBolus(carbs: 40, bolus: 3)))

        #expect(result.ackCode == .partialFailure)
        #expect(actions.storedCarbs.count == 1)
    }

    @Test("A failed meal carb save never reaches the bolus") func testMealBolusCarbsFailure() async {
        actions.carbsError = TestError("save failed")
        let result = await processor.process(request(.mealBolus(carbs: 40, bolus: 3)))

        #expect(result.ackCode == .genericFailure)
        #expect(validator.validatedAmounts.isEmpty)
        #expect(actions.enactedBoluses.isEmpty)
    }

    // MARK: - Deduplication

    @Test("A completed duplicate replays its result without executing again") func testCompletedDuplicate() async {
        let request = request(.bolus(1))

        let first = await processor.process(request)
        let second = await processor.process(request)

        #expect(first == second)
        #expect(actions.enactedBoluses.count == 1)
        #expect(validator.validatedAmounts.count == 1)
    }

    @Test("Rejections are cached as terminal results too") func testRejectionCached() async {
        settings.settings.isGarminCommandControlEnabled = false
        let request = request(.carbs(10))
        let first = await processor.process(request)

        settings.settings.isGarminCommandControlEnabled = true
        let second = await processor.process(request)

        #expect(first == second)
        #expect(actions.storedCarbs.isEmpty)
    }

    @Test("A duplicate of an in-flight request is rejected") func testInFlightDuplicate() async {
        let request = request(.bolus(1))
        let key = WatchCommandRequestCache.Key(appUUID: request.appUUID, requestID: request.requestID)
        _ = await cache.admit(key, command: request.command, now: now)

        let result = await processor.process(request)

        #expect(result.acknowledged == false)
        #expect(result.ackCode == .inProgress, "Watches tell a running duplicate apart by code, not by text")
        #expect(validator.validatedAmounts.isEmpty)
        #expect(actions.enactedBoluses.isEmpty)
    }

    @Test("Reusing a request ID for another command is rejected") func testConflict() async {
        let id = UUID()
        _ = await processor.process(request(.carbs(10), id: id))
        let result = await processor.process(request(.carbs(20), id: id))

        #expect(result.acknowledged == false)
        #expect(actions.storedCarbs.map(\.grams) == [10])
    }

    @Test("Request IDs are scoped per app") func testScopedPerApp() async {
        let id = UUID()
        _ = await processor.process(request(.carbs(10), id: id))
        _ = await processor.process(request(.carbs(10), id: id, app: UUID()))

        #expect(actions.storedCarbs.count == 2)
    }

    // MARK: - Adjustments

    @Test("Activating an override uses the exact preset and the watch source") func testActivateOverride() async {
        actions.overrides = [
            WatchPresetEntry(name: "Sport ", isActive: false, ref: .presetID("trailing")),
            WatchPresetEntry(name: "Sport", isActive: false, ref: .presetID("exact"))
        ]
        let result = await processor.process(request(.activateOverride(name: "Sport")))

        #expect(result == .success(.overrideStarted, result.message))
        #expect(adjustments.calls == [.activateOverride(.presetID("exact"))])
        #expect(adjustments.sources == [.watch])
    }

    @Test("An inactive preset can be activated; its state only reports whether it runs") func testInactivePresetActivates(
    ) async throws {
        actions.overrides = [WatchPresetEntry(name: "Sport", isActive: false, ref: .presetID("sport"))]
        actions.tempTargets = [WatchPresetEntry(name: "Walk", isActive: true, ref: .presetID("walk"))]

        #expect(await processor.process(request(.activateOverride(name: "Sport"))).ackCode == .overrideStarted)
        #expect(await processor.process(request(.activateTempTarget(name: "Walk"))).ackCode == .tempTargetStarted)
        #expect(adjustments.calls == [.activateOverride(.presetID("sport")), .activateTempTarget(.presetID("walk"))])

        let presets = try await processor.presets()
        #expect(presets.overridePresets == [OverridePresetWatch(name: "Sport", isEnabled: false)])
        #expect(presets.tempTargetPresets == [TempTargetPresetWatch(name: "Walk", isEnabled: true)])
    }

    @Test("Missing or ambiguous override names are rejected", arguments: ["Missing", "Sport"]) func testOverrideNotUnique(
        name: String
    ) async {
        actions.overrides = [
            WatchPresetEntry(name: "Sport", isActive: false, ref: .presetID("a")),
            WatchPresetEntry(name: "Sport", isActive: false, ref: .presetID("b"))
        ]
        let result = await processor.process(request(.activateOverride(name: name)))

        #expect(result.acknowledged == false)
        #expect(adjustments.calls.isEmpty)
    }

    @Test("Cancelling with nothing active is an idempotent success") func testCancelIdempotent() async {
        adjustments.error = AdjustmentError.nothingActive

        let override = await processor.process(request(.cancelOverride))
        let tempTarget = await processor.process(request(.cancelTempTarget))

        #expect(override == .success(.overrideStopped, override.message))
        #expect(tempTarget == .success(.tempTargetStopped, tempTarget.message))
    }

    @Test("Other cancellation errors are failures") func testCancelFailure() async {
        adjustments.error = AdjustmentError.persistenceFailed("disk full")
        let result = await processor.process(request(.cancelOverride))

        #expect(result.acknowledged == false)
        #expect(!result.message.contains("disk full"), "Internal errors never reach the watch")
    }

    @Test("Activating a temp target uses the exact preset") func testActivateTempTarget() async {
        actions.tempTargets = [WatchPresetEntry(name: "Walk", isActive: false, ref: .presetID("walk"))]
        let result = await processor.process(request(.activateTempTarget(name: "Walk")))

        #expect(result == .success(.tempTargetStarted, result.message))
        #expect(adjustments.calls == [.activateTempTarget(.presetID("walk"))])
    }

    // MARK: - Presets

    @Test("Presets are sorted by name and keep their state") func testPresetsSorted() async throws {
        actions.overrides = [
            WatchPresetEntry(name: "b", isActive: false, ref: .presetID("b")),
            WatchPresetEntry(name: "A", isActive: true, ref: .presetID("A")),
            WatchPresetEntry(name: "c", isActive: false, ref: .presetID("c"))
        ]
        actions.tempTargets = [
            WatchPresetEntry(name: "Walk 10", isActive: false, ref: .presetID("10")),
            WatchPresetEntry(name: "Walk 9", isActive: false, ref: .presetID("9"))
        ]

        let presets = try await processor.presets()

        #expect(presets.overridePresets == [
            OverridePresetWatch(name: "A", isEnabled: true),
            OverridePresetWatch(name: "b", isEnabled: false),
            OverridePresetWatch(name: "c", isEnabled: false)
        ])
        #expect(presets.tempTargetPresets.map(\.name) == ["Walk 9", "Walk 10"])
    }

    @Test("Presets stay readable with commands disabled") func testPresetsIgnoreMasterSwitch() async throws {
        settings.settings.isGarminCommandControlEnabled = false
        actions.overrides = [WatchPresetEntry(name: "Sport", isActive: false, ref: .presetID("s"))]

        #expect(try await processor.presets().overridePresets.count == 1)
    }

    @Test("Presets carry the command switches and limits as they are at call time") func testPresetsCapabilities(
    ) async throws {
        settings.settings.isGarminCommandControlEnabled = true
        settings.settings.isGarminBolusCommandEnabled = true
        settings.settings.maxCarbs = 120
        settings.pumpSettings = PumpSettings(insulinActionCurve: 10, maxBolus: 5, maxBasal: 2)
        settings.preferences.bolusIncrement = 0.1

        #expect(try await processor.presets().capabilities == WatchCommandCapabilities(
            isCommandControlEnabled: true,
            isBolusCommandEnabled: true,
            maxBolus: 5,
            maxCarbs: 120,
            bolusIncrement: 0.1
        ))

        settings.settings.isGarminCommandControlEnabled = false
        #expect(try await processor.presets().capabilities.isCommandControlEnabled == false)
    }

    // MARK: - Revocation

    @Test(
        "Disabling commands while meal carbs save stops the bolus and reports a partial failure"
    ) func testMasterRevokedDuringMealCarbs() async {
        actions.carbsGate = TestGate()
        let pending = Task { await processor.process(request(.mealBolus(carbs: 40, bolus: 3))) }
        await actions.carbsGate.waitForArrivals()

        settings.settings.isGarminCommandControlEnabled = false
        actions.carbsGate.open()
        let result = await pending.value

        #expect(result.ackCode == .partialFailure)
        #expect(actions.storedCarbs.map(\.grams) == [40])
        #expect(validator.validatedAmounts.isEmpty)
        #expect(actions.enactedBoluses.isEmpty)
    }

    @Test(
        "Disabling bolus while validation is pending stops the bolus",
        arguments: [false, true]
    ) func testBolusRevokedDuringValidation(isMeal: Bool) async {
        validator.gate = TestGate()
        let command: WatchCommand = isMeal ? .mealBolus(carbs: 40, bolus: 3) : .bolus(3)
        let pending = Task { await processor.process(request(command)) }
        await validator.gate.waitForArrivals()

        settings.settings.isGarminBolusCommandEnabled = false
        validator.gate.open()
        let result = await pending.value

        #expect(result.acknowledged == false)
        #expect(result.ackCode == (isMeal ? .partialFailure : .genericFailure))
        #expect(actions.enactedBoluses.isEmpty, "No insulin after the bolus switch went off")
    }

    @Test(
        "Switching either setting off and on again while pending still revokes",
        arguments: [false, true]
    ) func testRevokedAndReenabled(bolusSwitch: Bool) async {
        validator.gate = TestGate()
        let pending = Task { await processor.process(request(.bolus(2))) }
        await validator.gate.waitForArrivals()

        // the setter revokes; nothing else is called
        if bolusSwitch {
            settings.settings.isGarminBolusCommandEnabled = false
            settings.settings.isGarminBolusCommandEnabled = true
        } else {
            settings.settings.isGarminCommandControlEnabled = false
            settings.settings.isGarminCommandControlEnabled = true
        }
        validator.gate.open()
        let result = await pending.value

        #expect(result.acknowledged == false)
        #expect(actions.enactedBoluses.isEmpty)

        #expect(await processor.process(request(.carbs(10))).acknowledged, "New commands run under the new settings")
    }

    @Test("Turning a setting on revokes nothing") func testEnablingKeepsGrant() {
        settings.settings.isGarminCommandControlEnabled = false
        let epoch = settings.authorization.current

        settings.settings.isGarminCommandControlEnabled = true
        settings.settings.maxCarbs = 80

        #expect(settings.authorization.current == epoch)
    }

    @Test("Disabling commands while presets load stops the activation") func testRevokedDuringPresetLoad() async {
        actions.overrides = [WatchPresetEntry(name: "Sport", isActive: false, ref: .presetID("sport"))]
        actions.presetsGate = TestGate()
        let pending = Task { await processor.process(request(.activateOverride(name: "Sport"))) }
        await actions.presetsGate.waitForArrivals()

        settings.settings.isGarminCommandControlEnabled = false
        settings.settings.isGarminCommandControlEnabled = true
        actions.presetsGate.open()

        #expect(await pending.value.acknowledged == false)
        #expect(adjustments.calls.isEmpty)
    }

    // MARK: - Final Boundary

    @Test(
        "A revocation while an adjustment waits for the serializer stops it before the write",
        arguments: [
            WatchCommand.activateOverride(name: "Sport"), .cancelOverride,
            .activateTempTarget(name: "Walk"), .cancelTempTarget
        ]
    ) func testAdjustmentRevokedWhileQueued(command: WatchCommand) async {
        actions.overrides = [WatchPresetEntry(name: "Sport", isActive: false, ref: .presetID("sport"))]
        actions.tempTargets = [WatchPresetEntry(name: "Walk", isActive: false, ref: .presetID("walk"))]
        adjustments.gate = TestGate()
        let pending = Task { await processor.process(request(command)) }
        await adjustments.gate.waitForArrivals()

        settings.settings.isGarminCommandControlEnabled = false
        settings.settings.isGarminCommandControlEnabled = true
        adjustments.gate.open()
        let result = await pending.value

        #expect(result.acknowledged == false)
        #expect(result.ackCode == .genericFailure)
        #expect(adjustments.calls.isEmpty)
    }

    @Test(
        "A revocation while carbs wait for their transaction stores nothing",
        arguments: [false, true]
    ) func testCarbsRevokedBeforeTransaction(isMeal: Bool) async {
        actions.carbsTransactionGate = TestGate()
        let command: WatchCommand = isMeal ? .mealBolus(carbs: 40, bolus: 3) : .carbs(40)
        let pending = Task { await processor.process(request(command)) }
        await actions.carbsTransactionGate.waitForArrivals()

        settings.settings.isGarminCommandControlEnabled = false
        settings.settings.isGarminCommandControlEnabled = true
        actions.carbsTransactionGate.open()
        let result = await pending.value

        #expect(result.ackCode == .genericFailure, "Nothing was logged, so this is no partial failure")
        #expect(actions.events.isEmpty)
        #expect(validator.validatedAmounts.isEmpty)
    }

    @Test(
        "A revocation after validation but before issuance sends nothing to the pump",
        arguments: [false, true]
    ) func testRevokedBeforeIssuance(isMeal: Bool) async {
        actions.issueGate = TestGate()
        let command: WatchCommand = isMeal ? .mealBolus(carbs: 40, bolus: 3) : .bolus(3)
        let pending = Task { await processor.process(request(command)) }
        await actions.issueGate.waitForArrivals()
        #expect(validator.validatedAmounts == [3], "Validation already passed")

        settings.settings.isGarminBolusCommandEnabled = false
        settings.settings.isGarminBolusCommandEnabled = true
        actions.issueGate.open()
        let result = await pending.value

        #expect(result.acknowledged == false)
        #expect(result.ackCode == (isMeal ? .partialFailure : .genericFailure))
        #expect(actions.storedCarbs.map(\.grams) == (isMeal ? [40] : []))
        #expect(actions.enactedBoluses.isEmpty)
    }

    @Test("A bolus stopped before issuance does not hold the lane") func testFinalCheckWithdrawsLaneHold() async {
        actions.issueGate = TestGate()
        let pending = Task { await processor.process(request(.bolus(3))) }
        await actions.issueGate.waitForArrivals()
        settings.settings.isGarminBolusCommandEnabled = false
        settings.settings.isGarminBolusCommandEnabled = true
        actions.issueGate.open()
        #expect(await pending.value.acknowledged == false)

        #expect(await processor.process(request(.bolus(1))).acknowledged, "Nothing reached the pump, so no hold")
        #expect(actions.enactedBoluses == [1])
    }

    // MARK: - Freshness After Waiting

    @Test(
        "A request that expires while it waits in the lane is rejected before validation",
        arguments: [false, true]
    ) func testExpiredInLane(isMeal: Bool) async {
        validator.gate = TestGate()
        // the first bolus is refused, so the lane hold cannot be what stops the second
        validator.queuedResults = [.rejected(.exceedsMaxIOB(currentIOB: 4, maxIOB: 5)), .allowed]
        let lane = WatchCommandInsulinLane()
        let processor = Self.makeProcessor(container: container, actions: actions, insulinLane: lane, clock: clock, logs: logs)

        let first = Task { await processor.process(request(.bolus(2))) }
        await validator.gate.waitForArrivals()
        let command: WatchCommand = isMeal ? .mealBolus(carbs: 30, bolus: 1) : .bolus(1)
        let second = Task { await processor.process(request(command, age: 590)) }
        #expect(await eventually { await lane.waitingCount == 1 })

        clock.advance(by: 20)
        validator.gate.open()
        #expect(await first.value.acknowledged == false)
        let result = await second.value

        #expect(result.acknowledged == false)
        #expect(result.ackCode == (isMeal ? .partialFailure : .genericFailure))
        #expect(validator.validatedAmounts == [2], "The expired request never validates")
        #expect(actions.enactedBoluses.isEmpty)
        #expect(logs.lines.contains { $0.contains("outside the freshness window") })
    }

    @Test(
        "A request that expires during validation is not enacted",
        arguments: [false, true]
    ) func testExpiredDuringValidation(isMeal: Bool) async {
        validator.gate = TestGate()
        let command: WatchCommand = isMeal ? .mealBolus(carbs: 30, bolus: 1) : .bolus(1)
        let pending = Task { await processor.process(request(command, age: 595)) }
        await validator.gate.waitForArrivals()

        clock.advance(by: 10)
        validator.gate.open()
        let result = await pending.value

        #expect(result.ackCode == (isMeal ? .partialFailure : .genericFailure))
        #expect(actions.storedCarbs.count == (isMeal ? 1 : 0))
        #expect(actions.enactedBoluses.isEmpty)
    }

    @Test(
        "A request that expires right before issuance is not enacted",
        arguments: [false, true]
    ) func testExpiredBeforeIssuance(isMeal: Bool) async {
        actions.issueGate = TestGate()
        let command: WatchCommand = isMeal ? .mealBolus(carbs: 30, bolus: 1) : .bolus(1)
        let pending = Task { await processor.process(request(command, age: 599)) }
        await actions.issueGate.waitForArrivals()

        clock.advance(by: 2)
        actions.issueGate.open()
        let result = await pending.value

        #expect(result.ackCode == (isMeal ? .partialFailure : .genericFailure))
        #expect(actions.enactedBoluses.isEmpty)
    }

    @Test("An expired request replays its cached result without re-running") func testExpiredReplay() async {
        validator.gate = TestGate()
        let request = request(.bolus(1), age: 595)
        let pending = Task { await processor.process(request) }
        await validator.gate.waitForArrivals()
        clock.advance(by: 10)
        validator.gate.open()
        let first = await pending.value

        let replay = await processor.process(request)

        #expect(replay == first)
        #expect(validator.validatedAmounts.count == 1)
    }

    // MARK: - Insulin Lane

    @Test("A second insulin request waits for the first and never validates alongside it") func testInsulinSerialized() async {
        let probe = InsulinConcurrencyProbe()
        validator.probe = probe
        actions.probe = probe
        validator.gate = TestGate()
        let lane = WatchCommandInsulinLane()
        let processor = Self.makeProcessor(container: container, actions: actions, insulinLane: lane, clock: clock, logs: logs)

        let first = Task { await processor.process(request(.bolus(2))) }
        await validator.gate.waitForArrivals()
        let second = Task { await processor.process(request(.mealBolus(carbs: 30, bolus: 2))) }
        #expect(await eventually { await lane.waitingCount == 1 }, "Second request is parked at the lane")
        #expect(validator.gate.arrivalCount == 1)

        validator.gate.open()
        let firstResult = await first.value
        let secondResult = await second.value

        #expect(firstResult.acknowledged)
        #expect(secondResult.ackCode == .partialFailure, "Its carbs are logged, its bolus is held back")
        #expect(actions.enactedBoluses == [2])
        #expect(probe.maximumInFlight == 1)
        #expect(probe.recordedEvents == ["validate", "enact"])
    }

    @Test("A request that waited validates afresh after the first finished") func testInsulinRevalidatedAfterWait() async {
        let probe = InsulinConcurrencyProbe()
        validator.probe = probe
        actions.probe = probe
        validator.gate = TestGate()
        validator.queuedResults = [.rejected(.exceedsMaxIOB(currentIOB: 4, maxIOB: 5)), .allowed]
        let lane = WatchCommandInsulinLane()
        let processor = Self.makeProcessor(container: container, actions: actions, insulinLane: lane, clock: clock, logs: logs)

        let first = Task { await processor.process(request(.bolus(2))) }
        await validator.gate.waitForArrivals()
        let second = Task { await processor.process(request(.bolus(1))) }
        #expect(await eventually { await lane.waitingCount == 1 })

        validator.gate.open()
        #expect(await first.value.acknowledged == false)
        #expect(await second.value.acknowledged)
        #expect(validator.validatedAmounts == [2, 1])
        #expect(actions.enactedBoluses == [1])
        #expect(probe.maximumInFlight == 1)
        #expect(probe.recordedEvents == ["validate", "validate", "enact"])
    }

    /// Phase 1 keeps the lane hold even when the pump refused the first bolus: a refusal can still
    /// mean partial delivery, and pump history may not show it yet.
    @Test(
        "A second insulin request waits while the pump works on the first, then is held back",
        arguments: [true, false]
    ) func testInsulinWaitsForPump(pumpSucceeds: Bool) async {
        let probe = InsulinConcurrencyProbe()
        validator.probe = probe
        actions.probe = probe
        actions.bolusGate = TestGate()
        actions.bolusSucceeds = pumpSucceeds
        let lane = WatchCommandInsulinLane()
        let processor = Self.makeProcessor(container: container, actions: actions, insulinLane: lane, clock: clock, logs: logs)

        let first = Task { await processor.process(request(.bolus(2))) }
        await actions.bolusGate.waitForArrivals()
        let second = Task { await processor.process(request(.bolus(1))) }
        #expect(await eventually { await lane.waitingCount == 1 }, "Parked while the pump request is open")
        #expect(validator.validatedAmounts == [2])

        actions.bolusGate.open()
        #expect(await first.value.acknowledged == pumpSucceeds)
        let secondResult = await second.value

        #expect(secondResult.acknowledged == false)
        #expect(logs.lines.contains { $0.contains("previous watch bolus may not be in pump history yet") })
        #expect(validator.validatedAmounts == [2], "Held back before validation")
        #expect(actions.enactedBoluses == [2])
        #expect(probe.maximumInFlight == 1)
    }

    // MARK: - Safe Logging

    @Test("Error details never reach the log or the ack") func testSensitiveErrorsSanitized() async {
        actions.carbsError = SensitiveTestError()
        adjustments.error = SensitiveTestError()
        actions.overrides = [WatchPresetEntry(name: "Sport", isActive: false, ref: .presetID("sport"))]

        let results = [
            await processor.process(request(.carbs(10))),
            await processor.process(request(.mealBolus(carbs: 10, bolus: 1))),
            await processor.process(request(.activateOverride(name: "Sport"))),
            await processor.process(request(.cancelOverride)),
            await processor.process(request(.cancelTempTarget))
        ]

        #expect(results.allSatisfy { !$0.acknowledged })
        #expect(results.allSatisfy { !$0.message.contains(SensitiveTestError.marker) })
        #expect(!logs.lines.isEmpty)
        #expect(logs.lines.allSatisfy { !$0.contains(SensitiveTestError.marker) && !$0.contains("42g") })
        #expect(logs.lines.contains { $0.contains("(unexpected)") })
    }

    @Test("Error categories are stable and content-free") func testErrorCategories() {
        #expect(WatchCommandErrorCategory.name(for: AdjustmentError.persistenceFailed("row 42")) == "adjustmentPersistence")
        #expect(WatchCommandErrorCategory.name(for: CoreDataError.fetchError(function: "f", file: "g")) == "coreData")
        let saveError = NSError(domain: NSCocoaErrorDomain, code: 134_030, userInfo: ["detail": SensitiveTestError.marker])
        #expect(WatchCommandErrorCategory.name(for: saveError) == "cocoa(134030)")
        #expect(WatchCommandErrorCategory.name(for: SensitiveTestError()) == "unexpected")
    }
}
