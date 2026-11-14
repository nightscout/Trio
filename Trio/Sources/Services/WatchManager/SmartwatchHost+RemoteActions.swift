import Foundation
import LoopKit
import os

/// Requests from the watch plugin: boluses, carbs, overrides, temp targets and
/// snoozes. Each gets the checks Trio applies to any request of that kind, such
/// as Max Bolus, Max IOB and Max Carbs, and only the current watch manager's
/// requests are acted on. Whether the watch may ask at all, and how fresh or
/// frequent its requests must be, is the plugin's own setting and policy
/// (LoopKit's `SmartwatchRemoteActionPolicy.swift` with the plugin's limits).
/// Every request and its outcome goes to the device log.
extension BaseSmartwatchHost {
    // MARK: - Watch bolus

    /// Delivers a bolus the plugin passed on, through the same path as Trio's
    /// Apple Watch app: only for the current watch manager, one at a time, within
    /// Trio's bolus safety checks (Max Bolus and Max IOB), rounded to a volume the
    /// pump supports. Returns once the pump accepted the bolus (it may still be
    /// cancelled while it runs): anything else, uncertain delivery included, is
    /// thrown as `.deliveryFailed`. Every other
    /// error is thrown before the pump is asked, so nothing was sent to it.
    @MainActor func smartwatchManager(_ manager: SmartwatchManager, deliverBolus units: Double) async throws -> Double {
        log(manager, .receive, String(format: "Bolus request: %.3f U", units))
        guard isCurrentWatch(manager) else {
            log(manager, .error, "Bolus request rejected: notAllowed (the request isn't from the current watch)")
            throw SmartwatchBolusError.notAllowed
        }
        // Checked and set with no suspension in between, so two requests can't
        // both pass.
        guard !isDeliveringWatchBolus else {
            log(manager, .error, "Bolus request answered with inProgress: a watch bolus is still being delivered")
            throw SmartwatchBolusError.inProgress
        }
        guard units.isFinite, units > 0 else {
            log(manager, .error, "Bolus request rejected: invalidAmount")
            throw SmartwatchBolusError.invalidAmount
        }
        guard let pumpManager = deviceDataManager.pumpManager else {
            log(manager, .error, "Bolus request rejected: no pump")
            throw SmartwatchBolusError.refusedByHost("no pump")
        }
        let rounded = pumpManager.roundToSupportedBolusVolume(units: units)
        let maximumBolus = Double(truncating: settingsManager.pumpSettings.maxBolus as NSNumber)
        // Both the amount asked for and the one delivered, whichever way the pump
        // rounds. Trio's bolus safety checks below check Max Bolus again.
        guard units <= maximumBolus, rounded <= maximumBolus else {
            log(manager, .error, String(
                format: "Bolus request rejected: exceedsMaximumBolus (%.3f U, rounded %.3f U; Max Bolus %.2f U)",
                units,
                rounded,
                maximumBolus
            ))
            throw SmartwatchBolusError.exceedsMaximumBolus
        }
        guard rounded > 0 else {
            log(manager, .error, String(format: "Bolus request rejected: invalidAmount (%.3f U rounds to 0 U)", units))
            throw SmartwatchBolusError.invalidAmount
        }

        // Taken before the checks below, so a request that arrives while they run
        // gets inProgress instead of passing them too.
        isDeliveringWatchBolus = true
        defer { isDeliveringWatchBolus = false }

        // Trio's bolus safety checks for Max Bolus and Max IOB. Their recent-bolus
        // check (20 % within 6 minutes) is for remote commands and Shortcuts, which
        // can arrive late or twice from someone who can't see what was just given;
        // like Trio's Apple Watch app, a watch bolus goes without it. With it, a
        // small bolus for more carbs was refused after almost every SMB. A window
        // starting now leaves that check nothing to count.
        //
        // What stands in for it no longer runs here but in the watch plugin, with
        // LoopKit's `SmartwatchBolusPolicy` and the plugin's own limits: the bolus
        // was confirmed on the watch moments ago, against a context issued from
        // Trio's current recommendation (which counts insulin given since the
        // determination, `smartwatchManager(_:recommendBolusForCarbs:)`), with
        // recent glucose, at most that recommendation, and at most one every few
        // minutes. Trio relies on the plugin for that freshness and pacing; here it
        // keeps Max Bolus, Max IOB, one bolus at a time and a truthful outcome.
        do {
            if case let .rejected(reason) = try await bolusSafetyValidator
                .validate(bolusAmount: Decimal(rounded), lookbackStart: Date())
            {
                log(manager, .error, "Bolus request rejected by Trio's bolus safety checks: \(reason)")
                throw Self.bolusError(for: reason)
            }
        } catch let error as SmartwatchBolusError {
            throw error
        } catch {
            log(manager, .error, "Bolus request rejected: Trio's bolus safety checks failed (\(error))")
            throw SmartwatchBolusError.refusedByHost(String(describing: error))
        }

        // Checked again after the await above, right before the pump call, so a
        // watch removed meanwhile can't bolus.
        guard isCurrentWatch(manager) else {
            log(manager, .error, "Bolus request rejected just before delivery: notAllowed (the watch was removed)")
            throw SmartwatchBolusError.notAllowed
        }
        log(manager, .delegate, String(format: "Delivering watch bolus of %.3f U (Max Bolus %.2f U)", rounded, maximumBolus))

        // Answered as soon as the pump reports, not after the determination that
        // enactBolus runs after a manual bolus, which can outlast the watch's wait.
        let apsManager: APSManager = self.apsManager
        let outcome = await Self.pumpOutcome { callback in
            await apsManager.enactBolus(amount: rounded, isSMB: false, callback: callback)
        }
        guard outcome.success else {
            log(manager, .error, "Watch bolus delivery failed: \(outcome.message)")
            signal(.loop)
            throw SmartwatchBolusError.deliveryFailed(outcome.message)
        }
        log(manager, .delegateResponse, String(format: "Watch bolus of %.3f U delivered", rounded))
        signal(.loop)
        return rounded
    }

    /// What Trio would recommend with the carbs the user is about to add from the
    /// watch (0 for none), without adding them: Trio's bolus calculator, as for
    /// its Apple Watch app, with those carbs and any watch carbs no determination
    /// has counted yet, less insulin delivered since that determination. The
    /// plugin also asks with 0 g for the bolus context it checks a bolus against.
    @MainActor func smartwatchManager(
        _ manager: SmartwatchManager,
        recommendBolusForCarbs grams: Double,
        absorptionTime: TimeInterval?
    ) async throws -> Double {
        // With 0 g it's the plugin's read for its bolus context, made after every
        // change: logged only when the answer changes. The watch's own questions
        // come with carbs and are always logged.
        let isContextRead = grams == 0
        if !isContextRead {
            log(
                manager,
                .receive,
                String(format: "Bolus recommendation request with %.0f g of carbs", grams)
                    // Trio's carb model has no per-entry absorption time.
                    + (absorptionTime.map { String(format: ", %.0f min absorption (not used by Trio)", $0 / 60) } ?? "")
            )
        }
        guard isCurrentWatch(manager) else {
            log(manager, .error, "Bolus recommendation refused: the request isn't from the current watch")
            throw SmartwatchBolusError.notAllowed
        }
        let maximumGrams = Double(truncating: settingsManager.settings.maxCarbs as NSNumber)
        guard grams.isFinite, grams >= 0, grams <= maximumGrams else {
            log(manager, .error, String(
                format: "Bolus recommendation refused: %.0f g isn't a valid carb entry (Max Carbs %.0f g)",
                grams,
                maximumGrams
            ))
            throw SmartwatchBolusError.invalidAmount
        }
        let determination = (try? await latestDetermination()) ?? nil
        let now = Date()
        let countedBefore = determinationSighting.seenAt(calculatedAt: determination?.calculatedAt, now: now)
        watchCarbEntries = Self.uncountedWatchCarbs(watchCarbEntries, determinationDate: countedBefore, now: now)
        let result = await bolusCalculationManager.handleBolusCalculation(
            carbs: Decimal(watchCarbEntries.reduce(0) { $0 + $1.grams } + grams),
            useFattyMealCorrection: false,
            useSuperBolus: false,
            lastLoopDate: apsManager.lastLoopDate,
            minPredBG: determination?.minPredBG ?? 54,
            simulatedCOB: nil,
            isBackdated: false
        )
        let calculated = Double(truncating: result.insulinCalculated as NSNumber)
        let deliveredSince = await insulinDelivered(since: determination?.calculatedAt)
        let recommended = Self.watchRecommendation(calculated: calculated, deliveredSinceDetermination: deliveredSince)
        // Rounded as a bolus is rounded.
        let units = deviceDataManager.pumpManager?.roundToSupportedBolusVolume(units: recommended) ?? recommended
        let maximumBolus = Double(truncating: settingsManager.pumpSettings.maxBolus as NSNumber)
        if isContextRead, !contextRecommendationLog.shouldLog(units) {
            return units
        }
        if deliveredSince > 0 {
            log(manager, .delegateResponse, String(
                format: "Bolus recommendation: %.2f U less %.2f U delivered since the determination it uses",
                calculated,
                deliveredSince
            ))
        }
        log(manager, .delegateResponse, String(
            format: "Bolus recommendation with %.0f g of carbs: %.2f U (Max Bolus %.2f U)",
            grams,
            units,
            maximumBolus
        ))
        return units
    }

    struct WatchCarbEntry: Equatable {
        let date: Date
        let grams: Double
    }

    /// When the host first saw each determination, by its `deliverAt`. A
    /// determination is saved after it fetched its carbs, and the host sees it
    /// after it was saved, so a watch carb entry stored before then is in its COB
    /// or, at worst, treated as if it were.
    struct DeterminationSighting {
        private var calculatedAt: Date?
        private var seen: Date?

        /// When the determination calculated at `calculatedAt` was first seen;
        /// `now` for one not seen before, `nil` without a determination.
        mutating func seenAt(calculatedAt: Date?, now: Date) -> Date? {
            guard let calculatedAt else { return nil }
            if calculatedAt != self.calculatedAt {
                self.calculatedAt = calculatedAt
                seen = now
            }
            return seen
        }
    }

    /// The watch carb entries a determination doesn't count yet: those stored after
    /// `determinationDate`, when this host first saw it (`DeterminationSighting`).
    /// Entries over 30 minutes old are dropped too, so carbs are never counted
    /// twice and old ones don't raise the recommendation; both mistakes only lower it.
    ///
    /// Not `deliverAt`: Trio takes it before the determination fetches its carbs,
    /// so carbs stored in between are in its COB and were added again.
    static func uncountedWatchCarbs(_ entries: [WatchCarbEntry], determinationDate: Date?, now: Date) -> [WatchCarbEntry] {
        entries.filter { entry in
            entry.date > now.addingTimeInterval(-30 * 60) && determinationDate.map { entry.date > $0 } ?? true
        }
    }

    /// The calculator's recommendation less insulin delivered since the determination
    /// it uses was calculated (the SMB it decided on, a bolus since): that
    /// determination's IOB doesn't count it yet, so it would be recommended twice
    /// until the next loop.
    static func watchRecommendation(calculated: Double, deliveredSinceDetermination: Double) -> Double {
        max(0, calculated - deliveredSinceDetermination)
    }

    /// The watch's error for a rejection by Trio's bolus safety checks, so the
    /// plugin can tell the watch why (over Max Bolus, over Max IOB).
    static func bolusError(for rejection: BolusSafetyRejection) -> SmartwatchBolusError {
        switch rejection {
        case .recentBolusWithinWindow: .rateLimited
        case .exceedsMaxBolus: .exceedsMaximumBolus
        case .exceedsMaxIOB,
             .iobUnavailable: .refusedByHost(String(describing: rejection))
        }
    }

    /// Insulin delivered as boluses (SMBs included) since `date`; 0 without one.
    private func insulinDelivered(since date: Date?) async -> Double {
        guard let date, let total = try? await bolusSafetyValidator.fetchTotalRecentBolusAmount(since: date) else { return 0 }
        return Double(truncating: total as NSNumber)
    }

    struct BolusOutcome: Equatable {
        var success: Bool
        var message: String
    }

    /// The outcome `enact` passes to its callback, as soon as it does, while `enact`
    /// goes on in its own task. Failure if `enact` returns without calling it; only
    /// the first call counts.
    static func pumpOutcome(
        of enact: @escaping @Sendable(@escaping (Bool, String) -> Void) async -> Void
    ) async -> BolusOutcome {
        await withCheckedContinuation { continuation in
            let answered = OSAllocatedUnfairLock(initialState: false)
            let answer: @Sendable(BolusOutcome) -> Void = { outcome in
                let first = answered.withLock { done in
                    defer { done = true }
                    return !done
                }
                if first {
                    continuation.resume(returning: outcome)
                }
            }
            Task {
                await enact { success, message in
                    answer(BolusOutcome(success: success, message: message))
                }
                answer(BolusOutcome(success: false, message: "no answer from the pump"))
            }
        }
    }

    // MARK: - Carbs

    /// Adds a carb entry like a remote meal, dated when the user confirmed it on
    /// the watch, within Max Carbs.
    @MainActor func smartwatchManager(
        _ manager: SmartwatchManager,
        addCarbEntry grams: Double,
        absorptionTime: TimeInterval?,
        date: Date
    ) async throws -> Double {
        log(
            manager,
            .receive,
            String(format: "Carb entry request: %.0f g, confirmed at %@", grams, String(describing: date))
                // Trio's carb model has no per-entry absorption time.
                + (absorptionTime.map { String(format: ", %.0f min absorption (not used by Trio)", $0 / 60) } ?? "")
        )
        guard isCurrentWatch(manager) else {
            log(manager, .error, "Carb entry request rejected: notAllowed (the request isn't from the current watch)")
            throw SmartwatchCarbEntryError.notAllowed
        }
        guard grams.isFinite, grams > 0 else {
            log(manager, .error, "Carb entry request rejected: invalidAmount")
            throw SmartwatchCarbEntryError.invalidAmount
        }
        let maximumGrams = Double(truncating: settingsManager.settings.maxCarbs as NSNumber)
        guard grams <= maximumGrams else {
            log(manager, .error, String(format: "Carb entry request rejected: exceedsMaximum (Max Carbs %.0f g)", maximumGrams))
            throw SmartwatchCarbEntryError.exceedsMaximum
        }
        do {
            let entry = carbsStorage.makeCarbEntry(carbs: Decimal(grams), date: date)
            try await carbsStorage.storeCarbs([entry], areFetchedFromRemote: false)
        } catch {
            log(manager, .error, "Watch carb entry failed: \(error)")
            throw SmartwatchCarbEntryError.failed(String(describing: error))
        }
        // Counted from when it was stored: a determination from before then can't include it.
        watchCarbEntries.append(WatchCarbEntry(date: Date(), grams: grams))
        log(manager, .delegateResponse, String(format: "Watch carb entry of %.0f g added", grams))
        signal(.loop)
        return grams
    }

    // MARK: - Snooze

    /// The longest snooze a watch can ask for.
    static let maximumMuteDuration: TimeInterval = 4 * 60 * 60

    /// Snoozes Trio's alerts like every other snooze surface, for at most 4 hours;
    /// a duration of 0 ends the snooze. Critical alerts still sound, as for any snooze.
    @MainActor func smartwatchManager(_ manager: SmartwatchManager, muteAlertsFor duration: TimeInterval) async throws -> Date {
        log(manager, .receive, String(format: "Mute request: %.0f min", duration / 60))
        guard isCurrentWatch(manager) else {
            log(manager, .error, "Mute request rejected: notAllowed (the request isn't from the current watch)")
            throw SmartwatchAlertMuteError.notAllowed
        }
        guard duration.isFinite, duration >= 0 else {
            log(manager, .error, "Mute request rejected: invalid duration")
            throw SmartwatchAlertMuteError.notAllowed
        }
        if duration == 0 {
            await trioAlertManager.applySnooze(for: 0)
            log(manager, .delegateResponse, "Snooze ended from the watch")
            return Date()
        }
        let muteDuration = min(duration, Self.maximumMuteDuration)
        await trioAlertManager.applySnooze(for: muteDuration)
        let end = Date().addingTimeInterval(muteDuration)
        log(manager, .delegateResponse, String(format: "Alerts snoozed from the watch for %.0f min", muteDuration / 60))
        return end
    }

    // MARK: - Overrides and temp targets

    @MainActor func smartwatchManager(_ manager: SmartwatchManager, enactOverride action: SmartwatchPresetAction) async throws {
        try await handlePresetRequest(
            kind: "Override",
            action: action,
            from: manager,
            activate: { try await self.adjustmentManager.activateOverride(.presetID($0), source: .watch) },
            cancel: { try await self.adjustmentManager.cancelOverride(source: .watch) }
        )
    }

    @MainActor func smartwatchManager(_ manager: SmartwatchManager, enactTempTarget action: SmartwatchPresetAction) async throws {
        try await handlePresetRequest(
            kind: "Temp target",
            action: action,
            from: manager,
            activate: { try await self.adjustmentManager.activateTempTarget(.presetID($0), source: .watch) },
            cancel: { try await self.adjustmentManager.cancelTempTarget(source: .watch) }
        )
    }

    /// Starts or ends a preset through the same path as Trio's Apple Watch app,
    /// only for the current watch.
    @MainActor private func handlePresetRequest(
        kind: String,
        action: SmartwatchPresetAction,
        from manager: SmartwatchManager,
        activate: (String) async throws -> AdjustmentOutcome,
        cancel: () async throws -> AdjustmentOutcome
    ) async throws {
        let description = switch action {
        case let .activate(presetID): "start preset \(presetID)"
        case .cancel: "end the running one"
        }
        log(manager, .receive, "\(kind) request: \(description)")
        guard isCurrentWatch(manager) else {
            log(manager, .error, "\(kind) request rejected: notAllowed (the request isn't from the current watch)")
            throw SmartwatchPresetError.notAllowed
        }
        do {
            switch action {
            case let .activate(presetID):
                let outcome = try await activate(presetID)
                log(manager, .delegateResponse, "\(kind) \"\(outcome.started?.name ?? presetID)\" started from the watch")
            case .cancel:
                _ = try await cancel()
                log(manager, .delegateResponse, "\(kind) ended from the watch")
            }
        } catch AdjustmentError.nothingActive {
            // Nothing to end is what the user asked for.
            log(manager, .delegateResponse, "\(kind) end requested from the watch: nothing was running")
        } catch AdjustmentError.presetNotFound {
            log(manager, .error, "\(kind) request rejected: unknownPreset")
            throw SmartwatchPresetError.unknownPreset
        } catch {
            log(manager, .error, "\(kind) request from the watch failed: \(error)")
            throw SmartwatchPresetError.failed(String(describing: error))
        }
        signal(.presets)
    }
}
