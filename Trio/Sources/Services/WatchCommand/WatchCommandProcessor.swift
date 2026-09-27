import Foundation
import Swinject

/// Validates and executes watch commands independent of the transport that delivered them.
protocol WatchCommandProcessor {
    /// Runs `request` at most once per app and request ID and returns its terminal result;
    /// a duplicate gets the cached result back without executing again.
    func process(_ request: WatchCommandRequest) async -> WatchCommandResult

    /// Override and temp target presets, sorted by display name, with the current command switches
    /// and limits.
    func presets() async throws -> WatchCommandPresets
}

/// Revocation epoch for watch commands; a command admitted under an older epoch was revoked.
///
/// `BaseSettingsManager` advances it synchronously from the settings setter, on whatever queue
/// writes the settings, before a Garmin command setting that turns off is stored. The settings
/// notification is asynchronous and carries only the latest value, so an off-then-on sequence
/// that lands before the main queue drains would otherwise revoke nothing.
final class WatchCommandAuthorization {
    private let lock = NSLock()
    private var epoch: UInt64 = 0

    var current: UInt64 { lock.withLock { epoch } }

    /// Call before `new` is stored. Turning either setting off always revokes, even when it is
    /// switched back on right after; turning one on never does.
    func settingsWillChange(from old: TrioSettings, to new: TrioSettings) {
        let masterTurnedOff = old.isGarminCommandControlEnabled && !new.isGarminCommandControlEnabled
        let bolusTurnedOff = old.isGarminBolusCommandEnabled && !new.isGarminBolusCommandEnabled
        guard masterTurnedOff || bolusTurnedOff else { return }
        lock.withLock { epoch += 1 }
        debug(.watchManager, "⌚️🔐 Garmin: Command setting switched off - pending commands revoked")
    }
}

/// Thrown by the final check a side effect runs right before it writes or issues anything;
/// nothing was saved or sent to the pump.
struct WatchCommandRejection: Error {
    let result: WatchCommandResult
}

/// Admits one watch insulin command at a time across all request IDs, so each validation sees the
/// previous command's delivery. Waiters suspend on a continuation and never hold the actor.
///
/// Phase 1 policy, deliberately stricter than the shared 20% recent-bolus threshold: once a watch
/// bolus was handed to `APSManager`, the next watch insulin command is rejected for
/// `BolusSafetyEvaluator.recentBolusWindowMinutes`, even when the pump or status check refused it,
/// since pump history may not show it yet and a refusal can still mean partial delivery. Only a
/// final-check rejection, which never reached `APSManager`, withdraws the record.
actor WatchCommandInsulinLane {
    private var isOccupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Last pump request issued through the lane; pump history may not show it yet.
    private(set) var lastEnactment: Date?

    var waitingCount: Int { waiters.count }

    func enter() async {
        guard isOccupied else {
            isOccupied = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Hands the lane straight to the next waiter, so no newcomer can slip in between.
    func leave() {
        if waiters.isEmpty {
            isOccupied = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    func recordEnactment(at date: Date) {
        lastEnactment = date
    }

    /// Puts back what `recordEnactment` replaced when the request never reached the pump.
    func restoreEnactment(_ date: Date?) {
        lastEnactment = date
    }
}

/// Garmin is the only caller in phase 1, so the command gates read the Garmin settings.
final class BaseWatchCommandProcessor: WatchCommandProcessor, Injectable {
    /// Matches the remote-control freshness window and leaves room for the Connect IQ relay.
    static let maximumCommandAge: TimeInterval = 10 * 60
    /// Clock skew tolerance for watches that run slightly ahead of the phone.
    static let maximumCommandLead: TimeInterval = 60

    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var bolusSafetyValidator: BolusSafetyValidator!
    @Injected() private var adjustmentManager: AdjustmentManager!
    @Injected() private var authorization: WatchCommandAuthorization!

    private let actions: WatchCommandActions
    private let cache: WatchCommandRequestCache
    private let insulinLane: WatchCommandInsulinLane
    private let now: () -> Date
    private let log: (String) -> Void

    init(
        resolver: Resolver,
        actions: WatchCommandActions? = nil,
        cache: WatchCommandRequestCache = WatchCommandRequestCache(),
        insulinLane: WatchCommandInsulinLane = WatchCommandInsulinLane(),
        now: @escaping () -> Date = Date.init,
        log: @escaping (String) -> Void = { debug(.watchManager, $0) }
    ) {
        self.actions = actions ?? BaseWatchCommandActions(resolver: resolver)
        self.cache = cache
        self.insulinLane = insulinLane
        self.now = now
        self.log = log
        injectServices(resolver)
    }

    func process(_ request: WatchCommandRequest) async -> WatchCommandResult {
        let key = WatchCommandRequestCache.Key(appUUID: request.appUUID, requestID: request.requestID)
        let name = request.command.name
        let grant = authorization.current

        let ticket: WatchCommandRequestCache.Ticket
        switch await cache.admit(key, command: request.command, now: now()) {
        case let .accepted(admitted):
            ticket = admitted
        case let .completed(result):
            log("⌚️⏱️ Garmin: Duplicate \(name) request - returning cached result")
            return result
        case .inProgress:
            log("⌚️⏱️ Garmin: Duplicate \(name) request still in progress - rejected")
            return WatchCommandResult(
                acknowledged: false,
                ackCode: .inProgress,
                message: String(localized: "Request is already in progress.", comment: "Watch command ack")
            )
        case .conflict:
            log("⌚️⏱️ Garmin: Request ID reused for a different command (\(name)) - rejected")
            return .failure(String(localized: "Request ID was already used.", comment: "Watch command ack"))
        case .full:
            log("⌚️⏱️ Garmin: Too many \(name) requests in progress - rejected")
            return .failure(String(localized: "Too many requests in progress. Please try again.", comment: "Watch command ack"))
        }

        let result = await execute(request, grant: grant)
        await cache.complete(ticket, result: result)

        if result.acknowledged {
            log("⌚️✅ Garmin: \(name) -> \(result.ackCode.rawValue)")
        } else {
            log("⌚️❌ Garmin: \(name) -> \(result.ackCode.rawValue)")
        }
        return result
    }

    func presets() async throws -> WatchCommandPresets {
        async let overrides = actions.overridePresets()
        async let tempTargets = actions.tempTargetPresets()

        return try await WatchCommandPresets(
            overridePresets: sortedByName(overrides).map { OverridePresetWatch(name: $0.name, isEnabled: $0.isActive) },
            tempTargetPresets: sortedByName(tempTargets).map { TempTargetPresetWatch(name: $0.name, isEnabled: $0.isActive) },
            capabilities: capabilities()
        )
    }

    /// Same sources as the Apple Watch state, read at call time so a switch turned off is reported
    /// off in the very next reply.
    private func capabilities() -> WatchCommandCapabilities {
        let settings = settingsManager.settings
        return WatchCommandCapabilities(
            isCommandControlEnabled: settings.isGarminCommandControlEnabled,
            isBolusCommandEnabled: settings.isGarminBolusCommandEnabled,
            maxBolus: settingsManager.pumpSettings.maxBolus,
            maxCarbs: settings.maxCarbs,
            bolusIncrement: settingsManager.preferences.bolusIncrement
        )
    }

    // MARK: - Validation

    private func execute(_ request: WatchCommandRequest, grant: UInt64) async -> WatchCommandResult {
        if let rejection = rejection(for: request, grant: grant) {
            return rejection
        }

        switch request.command {
        case let .bolus(units):
            return await bolus(units, request: request, grant: grant)
        case let .carbs(grams):
            return await carbs(grams, request: request, grant: grant)
        case let .mealBolus(grams, units):
            return await mealBolus(carbs: grams, bolus: units, request: request, grant: grant)
        case let .activateOverride(name):
            return await activateOverride(named: name, request: request, grant: grant)
        case .cancelOverride:
            return await cancelOverride(request: request, grant: grant)
        case let .activateTempTarget(name):
            return await activateTempTarget(named: name, request: request, grant: grant)
        case .cancelTempTarget:
            return await cancelTempTarget(request: request, grant: grant)
        }
    }

    /// Checks that need no side effects: freshness, feature gates and amount limits.
    private func rejection(for request: WatchCommandRequest, grant: UInt64) -> WatchCommandResult? {
        if let rejection = expiryRejection(for: request) ?? authorizationRejection(for: request, grant: grant) {
            return rejection
        }

        if let units = request.command.bolusAmount, units <= 0 {
            return .failure(String(localized: "Invalid bolus amount.", comment: "Watch command ack"))
        }

        if let grams = request.command.carbsAmount {
            guard grams > 0 else {
                return .failure(String(localized: "Invalid carbs amount.", comment: "Watch command ack"))
            }
            guard Decimal(grams) <= settingsManager.settings.maxCarbs else {
                log("⌚️❌ Garmin: \(request.command.name) rejected - carbs above max carbs")
                return .failure(String(localized: "Carbs exceed the maximum allowed.", comment: "Watch command ack"))
            }
        }

        return nil
    }

    /// Re-checked for insulin after every wait: queueing in the lane or waiting for validation can
    /// outlast the window the request was admitted in.
    private func expiryRejection(for request: WatchCommandRequest) -> WatchCommandResult? {
        let age = now().timeIntervalSince(request.date)
        guard age <= Self.maximumCommandAge, age >= -Self.maximumCommandLead else {
            log("⌚️⏱️ Garmin: \(request.command.name) timestamp outside the freshness window - rejected")
            return .failure(String(localized: "Command expired. Please try again.", comment: "Watch command ack"))
        }
        return nil
    }

    /// Re-read at every side-effect boundary: settings can change while a command is suspended.
    ///
    /// Settings are read before the epoch. The epoch advances before a switch-off is stored, so
    /// a check that still sees the setting on after an off-then-on sequence also sees the new epoch.
    private func authorizationRejection(for request: WatchCommandRequest, grant: UInt64) -> WatchCommandResult? {
        let name = request.command.name
        let garminSettings = settingsManager.settings.garminSettings
        guard authorization.current == grant else {
            log("⌚️🔐 Garmin: \(name) rejected - command settings changed while pending")
            return .failure(String(localized: "Watch command settings changed.", comment: "Watch command ack"))
        }

        guard garminSettings.isCommandControlEnabled else {
            log("⌚️🔐 Garmin: \(name) rejected - watch commands disabled")
            return .failure(String(localized: "Watch commands are disabled.", comment: "Watch command ack"))
        }
        guard !request.command.isInsulin || garminSettings.isBolusCommandEnabled else {
            log("⌚️🔐 Garmin: \(name) rejected - bolus commands disabled")
            return .failure(String(localized: "Bolus from watch is disabled.", comment: "Watch command ack"))
        }
        return nil
    }

    /// The linearization point of a command: side effects run this synchronously in their last
    /// serialized hop, inside the Core Data transaction or in the task that calls
    /// `APSManager.enactBolus`, with nothing awaited between the check and the write or issuance.
    /// Insulin re-checks the freshness window as well.
    private func finalCheck(for request: WatchCommandRequest, grant: UInt64) -> @Sendable() throws -> Void {
        { [self] in
            if request.command.isInsulin, let rejection = expiryRejection(for: request) {
                throw WatchCommandRejection(result: rejection)
            }
            if let rejection = authorizationRejection(for: request, grant: grant) {
                throw WatchCommandRejection(result: rejection)
            }
        }
    }

    // MARK: - Treatments

    private enum BolusOutcome {
        case delivered
        /// Nothing was sent to the pump.
        case rejected(String)
        /// The pump refused or errored; part of the bolus may still have been delivered.
        case failed
    }

    private func bolus(_ units: Decimal, request: WatchCommandRequest, grant: UInt64) async -> WatchCommandResult {
        switch await deliverBolus(units, request: request, grant: grant) {
        case .delivered:
            return .success(.genericSuccess, String(localized: "Bolus started.", comment: "Watch command ack"))
        case let .rejected(message):
            return .failure(message)
        case .failed:
            return .failure(String(localized: "Bolus failed. Check pump history before repeating.", comment: "Watch command ack"))
        }
    }

    private func carbs(_ grams: Int, request: WatchCommandRequest, grant: UInt64) async -> WatchCommandResult {
        if let rejection = authorizationRejection(for: request, grant: grant) {
            return rejection
        }
        do {
            try await actions.storeCarbs(grams, date: request.date, authorize: finalCheck(for: request, grant: grant))
            return .success(.carbsLogged, String(localized: "Carbs logged.", comment: "Watch command ack"))
        } catch let rejection as WatchCommandRejection {
            return rejection.result
        } catch {
            log("⌚️❌ Garmin: Storing carbs failed (\(WatchCommandErrorCategory.name(for: error)))")
            return .failure(String(localized: "Could not log carbs.", comment: "Watch command ack"))
        }
    }

    private func mealBolus(
        carbs grams: Int,
        bolus units: Decimal,
        request: WatchCommandRequest,
        grant: UInt64
    ) async -> WatchCommandResult {
        if let rejection = authorizationRejection(for: request, grant: grant) {
            return rejection
        }
        do {
            try await actions.storeCarbs(grams, date: request.date, authorize: finalCheck(for: request, grant: grant))
        } catch let rejection as WatchCommandRejection {
            return rejection.result
        } catch {
            log("⌚️❌ Garmin: Storing meal carbs failed (\(WatchCommandErrorCategory.name(for: error)))")
            return .failure(String(localized: "Could not log carbs. No bolus was delivered.", comment: "Watch command ack"))
        }

        switch await deliverBolus(units, request: request, grant: grant) {
        case .delivered:
            return .success(.genericSuccess, String(localized: "Carbs logged and bolus started.", comment: "Watch command ack"))
        case .rejected:
            return WatchCommandResult(
                acknowledged: false,
                ackCode: .partialFailure,
                message: String(localized: "Carbs logged. No bolus was delivered.", comment: "Watch command ack")
            )
        case .failed:
            return WatchCommandResult(
                acknowledged: false,
                ackCode: .partialFailure,
                message: String(
                    localized: "Carbs logged. Bolus failed, check pump history before repeating.",
                    comment: "Watch command ack"
                )
            )
        }
    }

    private func deliverBolus(_ units: Decimal, request: WatchCommandRequest, grant: UInt64) async -> BolusOutcome {
        await insulinLane.enter()
        let outcome = await deliverBolusInLane(units, request: request, grant: grant)
        await insulinLane.leave()
        return outcome
    }

    /// Only runs while holding the insulin lane; everything is re-checked because the wait for the
    /// lane can take as long as another command's validation and pump request.
    private func deliverBolusInLane(_ units: Decimal, request: WatchCommandRequest, grant: UInt64) async -> BolusOutcome {
        if let rejection = expiryRejection(for: request) ?? authorizationRejection(for: request, grant: grant) {
            return .rejected(rejection.message)
        }

        let recentWindow = Double(BolusSafetyEvaluator.recentBolusWindowMinutes * 60)
        let previousEnactment = await insulinLane.lastEnactment
        if let previousEnactment, now().timeIntervalSince(previousEnactment) < recentWindow {
            log("⌚️❌ Garmin: Bolus rejected - previous watch bolus may not be in pump history yet")
            return .rejected(BolusSafetyRejection.recentBolusWithinWindow(totalRecent: 0).watchMessage)
        }

        // cover every bolus since the watch sent the command, and never less than the standard window
        let lookbackStart = min(request.date, now().addingTimeInterval(-recentWindow))

        do {
            switch try await bolusSafetyValidator.validate(bolusAmount: units, lookbackStart: lookbackStart) {
            case .allowed:
                break
            case let .rejected(reason):
                log("⌚️❌ Garmin: Bolus rejected by safety check (\(reason.logName))")
                return .rejected(reason.watchMessage)
            }
        } catch {
            log("⌚️❌ Garmin: Bolus safety check failed (\(WatchCommandErrorCategory.name(for: error)))")
            return .rejected(String(localized: "Could not verify bolus safety.", comment: "Watch command ack"))
        }

        // validation awaited, so the request may have expired or been revoked meanwhile
        if let rejection = expiryRejection(for: request) ?? authorizationRejection(for: request, grant: grant) {
            return .rejected(rejection.message)
        }
        // recorded before the request, since a pump error can still mean partial delivery
        await insulinLane.recordEnactment(at: now())
        do {
            return try await actions.enactBolus(units, authorize: finalCheck(for: request, grant: grant)) ? .delivered : .failed
        } catch {
            // the final check stopped it before `APSManager`, so nothing reached the pump
            await insulinLane.restoreEnactment(previousEnactment)
            let message = (error as? WatchCommandRejection)?.result.message
            return .rejected(message ?? String(localized: "Could not verify bolus safety.", comment: "Watch command ack"))
        }
    }

    // MARK: - Adjustments

    private func activateOverride(named name: String, request: WatchCommandRequest, grant: UInt64) async -> WatchCommandResult {
        do {
            let presets = try await actions.overridePresets()
            guard let preset = uniquePreset(named: name, in: presets) else {
                log("⌚️❌ Garmin: Override preset missing or ambiguous")
                return .failure(String(localized: "Override preset not found.", comment: "Watch command ack"))
            }
            if let rejection = authorizationRejection(for: request, grant: grant) {
                return rejection
            }
            try await adjustmentManager.activateOverride(
                preset.ref,
                source: .watch,
                authorize: finalCheck(for: request, grant: grant)
            )
            return .success(.overrideStarted, String(localized: "Override started.", comment: "Watch command ack"))
        } catch let rejection as WatchCommandRejection {
            return rejection.result
        } catch {
            log("⌚️❌ Garmin: Activating override failed (\(WatchCommandErrorCategory.name(for: error)))")
            return .failure(String(localized: "Could not start override.", comment: "Watch command ack"))
        }
    }

    private func cancelOverride(request: WatchCommandRequest, grant: UInt64) async -> WatchCommandResult {
        if let rejection = authorizationRejection(for: request, grant: grant) {
            return rejection
        }
        do {
            try await adjustmentManager.cancelOverride(source: .watch, authorize: finalCheck(for: request, grant: grant))
        } catch let rejection as WatchCommandRejection {
            return rejection.result
        } catch AdjustmentError.nothingActive {
            // cancelling an inactive override already has the requested outcome
        } catch {
            log("⌚️❌ Garmin: Cancelling override failed (\(WatchCommandErrorCategory.name(for: error)))")
            return .failure(String(localized: "Could not stop override.", comment: "Watch command ack"))
        }
        return .success(.overrideStopped, String(localized: "Override stopped.", comment: "Watch command ack"))
    }

    private func activateTempTarget(named name: String, request: WatchCommandRequest, grant: UInt64) async -> WatchCommandResult {
        do {
            let presets = try await actions.tempTargetPresets()
            guard let preset = uniquePreset(named: name, in: presets) else {
                log("⌚️❌ Garmin: Temp target preset missing or ambiguous")
                return .failure(String(localized: "Temp target preset not found.", comment: "Watch command ack"))
            }
            if let rejection = authorizationRejection(for: request, grant: grant) {
                return rejection
            }
            try await adjustmentManager.activateTempTarget(
                preset.ref,
                source: .watch,
                authorize: finalCheck(for: request, grant: grant)
            )
            return .success(.tempTargetStarted, String(localized: "Temp target started.", comment: "Watch command ack"))
        } catch let rejection as WatchCommandRejection {
            return rejection.result
        } catch {
            log("⌚️❌ Garmin: Activating temp target failed (\(WatchCommandErrorCategory.name(for: error)))")
            return .failure(String(localized: "Could not start temp target.", comment: "Watch command ack"))
        }
    }

    private func cancelTempTarget(request: WatchCommandRequest, grant: UInt64) async -> WatchCommandResult {
        if let rejection = authorizationRejection(for: request, grant: grant) {
            return rejection
        }
        do {
            try await adjustmentManager.cancelTempTarget(source: .watch, authorize: finalCheck(for: request, grant: grant))
        } catch let rejection as WatchCommandRejection {
            return rejection.result
        } catch AdjustmentError.nothingActive {
            // cancelling an inactive temp target already has the requested outcome
        } catch {
            log("⌚️❌ Garmin: Cancelling temp target failed (\(WatchCommandErrorCategory.name(for: error)))")
            return .failure(String(localized: "Could not stop temp target.", comment: "Watch command ack"))
        }
        return .success(.tempTargetStopped, String(localized: "Temp target stopped.", comment: "Watch command ack"))
    }

    /// Exact, case-sensitive match that ignores whether the preset is running; unlike
    /// `AdjustmentManager`'s trimmed name lookup, two presets that only differ in whitespace must
    /// not let the watch start the wrong one.
    private func uniquePreset(named name: String, in presets: [WatchPresetEntry]) -> WatchPresetEntry? {
        let matches = presets.filter { $0.name == name }
        return matches.count == 1 ? matches.first : nil
    }

    private func sortedByName(_ presets: [WatchPresetEntry]) -> [WatchPresetEntry] {
        presets.sorted {
            switch $0.name.localizedStandardCompare($1.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            // tie-break on raw names so equal display names keep a stable order
            case .orderedSame: return $0.name < $1.name
            }
        }
    }
}

private extension BolusSafetyRejection {
    /// Case name only; the associated values are insulin amounts, which stay out of the log.
    var logName: String {
        switch self {
        case .exceedsMaxBolus: return "exceedsMaxBolus"
        case .iobUnavailable: return "iobUnavailable"
        case .exceedsMaxIOB: return "exceedsMaxIOB"
        case .recentBolusWithinWindow: return "recentBolusWithinWindow"
        }
    }

    var watchMessage: String {
        switch self {
        case .exceedsMaxBolus:
            return String(localized: "Bolus exceeds max bolus.", comment: "Watch command ack")
        case .iobUnavailable:
            return String(localized: "IOB unavailable. Bolus not delivered.", comment: "Watch command ack")
        case .exceedsMaxIOB:
            return String(localized: "Bolus would exceed max IOB.", comment: "Watch command ack")
        case .recentBolusWithinWindow:
            return String(localized: "A bolus was given in the last few minutes.", comment: "Watch command ack")
        }
    }
}
