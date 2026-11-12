import Combine
import CoreData
import Foundation
import LoopKit
import Swinject

/// Evaluates user-configured `GlucoseAlert`s on every new CGM reading and every
/// new determination, then issues / retracts alerts via `TrioAlertManager`.
/// Mirrors the LoopFollow alarm-list model — multiple alarms of the same type
/// are allowed, each with its own threshold / schedule / sound.
///
/// Lookup flow:
///   1. CGM update → fetch latest `GlucoseStored` + prior readings.
///      For each enabled alarm matching the current day/night window:
///        - urgentLow / low: latest ≤ threshold (+ optional persistence)
///        - high: latest ≥ threshold (+ optional persistence)
///        - fallingFast / risingFast: rate over the last 15 min ≥ threshold mg/dL per 5 min, within the glucose limit
///   2. Determination update → blend forecast at the alarm's predictive horizon
///      (forecastedLow: fixed 20 min) and compare to threshold.
///
/// Throttling + snooze are inherited from `TrioAlertManager.issueAlert`. The
/// coordinator additionally tracks per-alarm firing state so it can retract
/// the alert when the condition recovers (no flap-spam).
final class GlucoseAlertCoordinator: Injectable {
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var trioAlertManager: TrioAlertManager!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var fetchGlucoseManager: FetchGlucoseManager!

    private let evaluationQueue = DispatchQueue(label: "GlucoseAlertCoordinator.queue")
    private var firingAlertIDs: Set<UUID> = []
    private var subscriptions = Set<AnyCancellable>()
    @SyncAccess private var alertsSnapshot: [GlucoseAlert] = []
    @SyncAccess private var configurationSnapshot = GlucoseAlertConfiguration()

    /// 5 mg/dL recovery margin before we retract a fired alert. Prevents flap
    /// at the threshold boundary.
    static let recoveryMarginMgDL: Decimal = 5

    /// Pure breach predicate. Low family (low/urgentLow/forecastedLow) breaches
    /// when the value is at or below threshold; high breaches at or above.
    /// `carbsRequired` is determination-driven and evaluated separately.
    /// Extracted for unit testing — the instance evaluators call through here.
    static func breached(type: GlucoseAlertType, latestMgDL: Decimal, thresholdMgDL: Decimal) -> Bool {
        switch type {
        case .forecastedLow,
             .low,
             .urgentLow:
            return latestMgDL <= thresholdMgDL
        case .high:
            return latestMgDL >= thresholdMgDL
        case .carbsRequired,
             .fallingFast,
             .risingFast:
            return false
        }
    }

    /// Pure retract predicate. A fired low-family alert retracts once the value
    /// recovers to threshold + margin; a high alert once it falls to
    /// threshold - margin. Extracted for unit testing.
    static func shouldRetract(
        type: GlucoseAlertType,
        latestMgDL: Decimal,
        thresholdMgDL: Decimal,
        recoveryMarginMgDL: Decimal = recoveryMarginMgDL
    ) -> Bool {
        switch type {
        case .forecastedLow,
             .low,
             .urgentLow:
            return latestMgDL >= thresholdMgDL + recoveryMarginMgDL
        case .high:
            return latestMgDL <= thresholdMgDL - recoveryMarginMgDL
        case .carbsRequired,
             .fallingFast,
             .risingFast:
            return false
        }
    }

    /// Window the rate is measured over, ending at the latest reading.
    static let rateWindow: TimeInterval = 15 * 60
    /// Shortest span the rate is computed over. Rejects single-reading jumps.
    static let minimumRateSpan: TimeInterval = 10 * 60
    /// 5 mg/dL per 5 minutes recovery margin before a fired rate alert retracts.
    static let rateRecoveryMarginMgDLPer5Minutes: Decimal = 5

    /// Glucose rate of change in mg/dL per 5 minutes (negative = falling) between the
    /// newest reading and the oldest one within `rateWindow` of it. Nil with
    /// fewer than 3 readings, a span under `minimumRateSpan`, or when the
    /// latest reading no longer moves in the rate's direction. `readings` is
    /// newest first.
    static func rateMgDLPer5Minutes(readings: [(date: Date, glucose: Decimal)]) -> Decimal? {
        guard let newest = readings.first else { return nil }
        let windowed = readings.filter { newest.date.timeIntervalSince($0.date) <= rateWindow }
        guard windowed.count >= 3, let oldest = windowed.last else { return nil }
        let span = newest.date.timeIntervalSince(oldest.date)
        guard span >= minimumRateSpan else { return nil }
        let rate = (newest.glucose - oldest.glucose) / Decimal(span / (5 * 60))
        let latestDelta = windowed[0].glucose - windowed[1].glucose
        guard rate != 0, latestDelta != 0, (rate > 0) == (latestDelta > 0) else { return nil }
        return rate
    }

    /// Falling Fast breaches at or below -threshold while glucose is at or
    /// below its limit, Rising Fast at or above threshold while glucose is at
    /// or above its limit. Level-driven types never breach here.
    static func rateBreached(
        type: GlucoseAlertType,
        rateMgDLPer5Minutes: Decimal?,
        thresholdMgDLPer5Minutes: Decimal,
        latestMgDL: Decimal,
        glucoseLimitMgDL: Decimal?
    ) -> Bool {
        guard let rateMgDLPer5Minutes else { return false }
        switch type {
        case .fallingFast:
            return rateMgDLPer5Minutes <= -thresholdMgDLPer5Minutes && latestMgDL <= (glucoseLimitMgDL ?? latestMgDL)
        case .risingFast:
            return rateMgDLPer5Minutes >= thresholdMgDLPer5Minutes && latestMgDL >= (glucoseLimitMgDL ?? latestMgDL)
        default: return false
        }
    }

    /// Retracts once the rate slows by the margin, or can no longer be
    /// computed.
    static func rateShouldRetract(
        type: GlucoseAlertType,
        rateMgDLPer5Minutes: Decimal?,
        thresholdMgDLPer5Minutes: Decimal
    ) -> Bool {
        guard let rateMgDLPer5Minutes else { return true }
        switch type {
        case .fallingFast: return rateMgDLPer5Minutes > -thresholdMgDLPer5Minutes + rateRecoveryMarginMgDLPer5Minutes
        case .risingFast: return rateMgDLPer5Minutes < thresholdMgDLPer5Minutes - rateRecoveryMarginMgDLPer5Minutes
        default: return false
        }
    }

    static func alarmsToRetractWhenCGMOwnsAlerts(firing: Set<UUID>, in alarms: [GlucoseAlert]) -> [GlucoseAlert] {
        alarms.filter { firing.contains($0.id) && $0.type.isReadingDriven }
    }

    /// Readings older than this are considered stale and won't drive new
    /// alarms — matches `APSManager`'s loop-input freshness gate (12 min,
    /// allowing for one missed CGM transmission on a 5-min schedule).
    /// Without this gate, force-quitting the app and reopening it after a
    /// CGM blackout could fire an alarm based on a 19-min-old reading.
    private static let readingFreshnessWindow: TimeInterval = 12 * 60

    /// Suppresses evaluations for a short window after launch. `firingAlertIDs`
    /// isn't persisted across relaunches, so without this quiet window the
    /// first reading after launch would re-fire any in-flight alarm whose
    /// glucose is still past threshold. UN throttle dedupes the lock-screen
    /// notification (5-min window), but the in-app banner can re-pop. Skipping
    /// the first ~30s lets the picture settle.
    private static let launchQuietWindow: TimeInterval = 30
    private let launchedAt = Date()
    private var isInLaunchQuietWindow: Bool {
        Date().timeIntervalSince(launchedAt) < Self.launchQuietWindow
    }

    private var effectiveTrioAlertsEnabled: Bool {
        if configurationSnapshot.forceTrioAlertsWhenCGMProvidesOwn { return true }
        return !CGMManagerAlertOwnership.providesOwnGlucoseAlerts(
            manager: fetchGlucoseManager?.cgmManager,
            sourceType: fetchGlucoseManager?.cgmGlucoseSourceType ?? .none
        )
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        let store = GlucoseAlertsStore.shared
        alertsSnapshot = store.alerts
        configurationSnapshot = store.configuration
        store.$alerts
            .sink { [weak self] new in self?.alertsSnapshot = new }
            .store(in: &subscriptions)
        store.$configuration
            .sink { [weak self] new in self?.configurationSnapshot = new }
            .store(in: &subscriptions)
        broadcaster.register(DeterminationObserver.self, observer: self)
        broadcaster.register(SnoozeObserver.self, observer: self)
        broadcaster.register(GlucoseSnoozeObserver.self, observer: self)
        glucoseStorage.updatePublisher
            .sink { [weak self] _ in
                Task { [weak self] in await self?.evaluateGlucoseAlarms() }
            }
            .store(in: &subscriptions)
    }

    // MARK: - Reading-based evaluation

    /// Two-stage: async-fetch the latest value (Core Data perform), then hop
    /// onto `evaluationQueue` to mutate `firingAlertIDs` safely.
    private func evaluateGlucoseAlarms() async {
        guard !isInLaunchQuietWindow else { return }
        guard effectiveTrioAlertsEnabled else {
            retractReadingDrivenFiringAlarms()
            return
        }
        let readings = await fetchRecentReadings()
        guard let latest = readings.first,
              Date().timeIntervalSince(latest.date) <= Self.readingFreshnessWindow
        else { return }
        let rate = Self.rateMgDLPer5Minutes(
            readings: readings.filter { !$0.isManual }.map { (date: $0.date, glucose: $0.glucose) }
        )
        let snapshot = alertsSnapshot
        let configuration = configurationSnapshot
        let now = Date()
        evaluationQueue.async { [weak self] in
            self?.applyReadingBasedEvaluation(
                latestValue: latest.glucose,
                rateMgDLPer5Minutes: rate,
                snapshot: snapshot,
                configuration: configuration,
                now: now
            )
        }
    }

    private func applyReadingBasedEvaluation(
        latestValue: Decimal,
        rateMgDLPer5Minutes: Decimal?,
        snapshot: [GlucoseAlert],
        configuration: GlucoseAlertConfiguration,
        now: Date
    ) {
        dispatchPrecondition(condition: .onQueue(evaluationQueue))
        // Iterate in type priority order so we can suppress lesser low-family
        // alarms when a more severe one is firing (urgent low > low). Without
        // this, glucose=60 with both urgent-low (54) AND low (70) configured
        // would surface two in-app alerts for the same low event. Falling
        // Fast is likewise suppressed while either low alarm is firing, and
        // Rising Fast while High is.
        let sorted = snapshot.sorted { $0.type.priority < $1.type.priority }
        var urgentLowFiring = false
        var lowFiring = false
        var highFiring = false
        for alarm in sorted where alarm.type.isReadingDriven {
            if alarm.type == .low, urgentLowFiring {
                retractIfFiring(alarm)
                continue
            }
            if alarm.type == .fallingFast, urgentLowFiring || lowFiring {
                retractIfFiring(alarm)
                continue
            }
            if alarm.type == .risingFast, highFiring {
                retractIfFiring(alarm)
                continue
            }
            evaluateReadingBased(
                alarm,
                latestMgDL: latestValue,
                rateMgDLPer5Minutes: rateMgDLPer5Minutes,
                now: now,
                configuration: configuration
            )
            if alarm.type == .urgentLow, firingAlertIDs.contains(alarm.id) {
                urgentLowFiring = true
            }
            if alarm.type == .low, firingAlertIDs.contains(alarm.id) {
                lowFiring = true
            }
            if alarm.type == .high, firingAlertIDs.contains(alarm.id) {
                highFiring = true
            }
        }
    }

    private func evaluateReadingBased(
        _ alarm: GlucoseAlert,
        latestMgDL: Decimal,
        rateMgDLPer5Minutes: Decimal?,
        now: Date,
        configuration: GlucoseAlertConfiguration
    ) {
        guard alarm.shouldEvaluate, !isAlarmSnoozed(alarm, at: now),
              isActive(alarm, at: now, configuration: configuration)
        else {
            retractIfFiring(alarm)
            return
        }

        if alarm.type == .forecastedLow {
            return // handled via determinationDidUpdate
        }
        if alarm.type.isRateDriven {
            if Self.rateBreached(
                type: alarm.type,
                rateMgDLPer5Minutes: rateMgDLPer5Minutes,
                thresholdMgDLPer5Minutes: alarm.thresholdMgDL,
                latestMgDL: latestMgDL,
                glucoseLimitMgDL: alarm.glucoseLimitMgDL
            ) {
                fireIfNeeded(alarm, valueMgDL: latestMgDL)
            } else if firingAlertIDs.contains(alarm.id),
                      Self.rateShouldRetract(
                          type: alarm.type,
                          rateMgDLPer5Minutes: rateMgDLPer5Minutes,
                          thresholdMgDLPer5Minutes: alarm.thresholdMgDL
                      )
            {
                retractIfFiring(alarm)
            }
            return
        }
        let breached = Self.breached(
            type: alarm.type,
            latestMgDL: latestMgDL,
            thresholdMgDL: alarm.thresholdMgDL
        )

        if breached {
            fireIfNeeded(alarm, valueMgDL: latestMgDL)
        } else if shouldRetract(alarm, latestMgDL: latestMgDL) {
            retractIfFiring(alarm)
        }
    }

    // MARK: - Forecast-based evaluation

    private func evaluateForecast(_ determination: Determination) {
        guard !isInLaunchQuietWindow else { return }
        // No CGM-ownership guard here, unlike the reading path: a CGM app can
        // alarm on the current reading, but it cannot compute Trio's oref
        // forecast, so it can never cover this alarm. Same reasoning as
        // `evaluateCarbsRequired`, and it matches what the settings screen
        // shows the user — only reading-driven types move into the
        // "Handled by CGM App" section.
        let snapshot = alertsSnapshot
        let configuration = configurationSnapshot
        let now = Date()

        // Suppress forecasted-low if any urgent-low or low alarm is already
        // firing — the forecast came true (or worse), no point preempting
        // it with a second alert.
        let lowFamilyFiring = snapshot.contains { alarm in
            (alarm.type == .urgentLow || alarm.type == .low)
                && firingAlertIDs.contains(alarm.id)
        }

        for alarm in snapshot where alarm.type == .forecastedLow {
            if lowFamilyFiring {
                retractIfFiring(alarm)
                continue
            }
            evaluateForecastBased(alarm, determination: determination, now: now, configuration: configuration)
        }
    }

    private func evaluateForecastBased(
        _ alarm: GlucoseAlert,
        determination: Determination,
        now: Date,
        configuration: GlucoseAlertConfiguration
    ) {
        guard alarm.shouldEvaluate, !isAlarmSnoozed(alarm, at: now),
              isActive(alarm, at: now, configuration: configuration),
              let result = ForecastedGlucoseEvaluator.evaluate(determination: determination)
        else {
            retractIfFiring(alarm)
            return
        }

        if result.predictedGlucose <= alarm.thresholdMgDL {
            fireIfNeeded(alarm, valueMgDL: result.predictedGlucose)
        } else if shouldRetract(alarm, latestMgDL: result.predictedGlucose) {
            retractIfFiring(alarm)
        }
    }

    // MARK: - Carbs-required evaluation

    /// Mirrors `evaluateForecast` for the carbs-required alarms. The alarm
    /// threshold (grams, stored in `thresholdMgDL`) is independent from the
    /// tab badge's threshold — surfaces are configured separately so the
    /// user can have a low-threshold badge for awareness and a higher-
    /// threshold alarm for active interruption.
    private func evaluateCarbsRequired(_ determination: Determination) {
        guard !isInLaunchQuietWindow else { return }
        let snapshot = alertsSnapshot
        let configuration = configurationSnapshot
        let now = Date()
        let carbsReq: Decimal? = determination.carbsReq

        for alarm in snapshot where alarm.type == .carbsRequired {
            guard alarm.shouldEvaluate, !isAlarmSnoozed(alarm, at: now),
                  isActive(alarm, at: now, configuration: configuration)
            else {
                retractIfFiring(alarm)
                continue
            }
            guard let carbs = carbsReq, carbs >= alarm.thresholdMgDL else {
                retractIfFiring(alarm)
                continue
            }
            fireIfNeeded(alarm, valueMgDL: carbs)
        }
    }

    // MARK: - Issue / retract bookkeeping

    /// Called only from the evaluation queue (forecast + reading paths both
    /// dispatch through `evaluationQueue` before invoking the evaluators),
    /// so `firingAlertIDs` is serialized without an extra `.sync` hop.
    private func fireIfNeeded(_ alarm: GlucoseAlert, valueMgDL: Decimal) {
        dispatchPrecondition(condition: .onQueue(evaluationQueue))
        guard !firingAlertIDs.contains(alarm.id) else { return }
        firingAlertIDs.insert(alarm.id)

        let title = alarm.name.isEmpty ? alarm.type.displayName : alarm.name
        let body = bodyText(for: alarm, valueMgDL: valueMgDL)
        let content = Alert.Content(
            title: title,
            body: body,
            acknowledgeActionButtonLabel: String(localized: "OK")
        )
        let alert = Alert(
            identifier: alertID(for: alarm),
            foregroundContent: content,
            backgroundContent: content,
            trigger: .immediate,
            interruptionLevel: alarm.overridesSilenceAndDND ? .critical : .timeSensitive,
            sound: alarm.playsSound ? .sound(name: alarm.soundFilename) : nil
        )
        trioAlertManager.issueAlert(alert)
    }

    private func retractIfFiring(_ alarm: GlucoseAlert) {
        dispatchPrecondition(condition: .onQueue(evaluationQueue))
        guard firingAlertIDs.contains(alarm.id) else { return }
        firingAlertIDs.remove(alarm.id)
        trioAlertManager.retractAlert(identifier: alertID(for: alarm))
    }

    private func retractReadingDrivenFiringAlarms() {
        evaluationQueue.async { [weak self] in
            guard let self, !self.firingAlertIDs.isEmpty else { return }
            let toRetract = Self.alarmsToRetractWhenCGMOwnsAlerts(
                firing: self.firingAlertIDs,
                in: self.alertsSnapshot
            )
            for alarm in toRetract {
                self.retractIfFiring(alarm)
            }
        }
    }

    private func shouldRetract(_ alarm: GlucoseAlert, latestMgDL: Decimal) -> Bool {
        dispatchPrecondition(condition: .onQueue(evaluationQueue))
        guard firingAlertIDs.contains(alarm.id) else { return false }
        return Self.shouldRetract(
            type: alarm.type,
            latestMgDL: latestMgDL,
            thresholdMgDL: alarm.thresholdMgDL
        )
    }

    private func alertID(for alarm: GlucoseAlert) -> Alert.Identifier {
        let typeSlug: String
        switch alarm.type {
        case .urgentLow: typeSlug = "urgentLow"
        case .low: typeSlug = "low"
        case .fallingFast: typeSlug = "fallingFast"
        case .forecastedLow: typeSlug = "forecastedLow"
        case .high: typeSlug = "high"
        case .risingFast: typeSlug = "risingFast"
        case .carbsRequired: typeSlug = "carbsRequired"
        }
        return Alert.Identifier(
            managerIdentifier: BaseTrioAlertManager.managerIdentifier,
            alertIdentifier: "glucose.\(typeSlug).\(alarm.id.uuidString)"
        )
    }

    private func bodyText(for alarm: GlucoseAlert, valueMgDL: Decimal) -> String {
        let units = settingsManager.settings.units
        let valueString = valueMgDL.formatted(withUnits: units)
        let limitString = alarm.thresholdMgDL.formatted(withUnits: units)
        switch alarm.type {
        case .low,
             .urgentLow:
            return String(
                format: String(localized: "Glucose %1$@."),
                valueString, limitString
            )
        case .forecastedLow:
            return String(
                format: String(localized: "Your glucose may go below %2$@ in %1$d min."),
                ForecastedGlucoseEvaluator.defaultHorizonMinutes, limitString
            )
        case .high:
            return String(
                format: String(localized: "Glucose %1$@."),
                valueString, limitString
            )
        case .fallingFast:
            return String(
                format: String(localized: "Glucose %@, falling fast."),
                valueString
            )
        case .risingFast:
            return String(
                format: String(localized: "Glucose %@, rising fast."),
                valueString
            )
        case .carbsRequired:
            return String(
                format: String(localized: "To prevent LOW required %d g of carbs"),
                Int(NSDecimalNumber(decimal: valueMgDL).intValue)
            )
        }
    }

    // MARK: - Helpers

    private func isAlarmSnoozed(_ alarm: GlucoseAlert, at date: Date) -> Bool {
        guard let until = alarm.snoozedUntil else { return false }
        return until > date
    }

    private func isActive(_ alarm: GlucoseAlert, at date: Date, configuration: GlucoseAlertConfiguration) -> Bool {
        switch alarm.activeOption {
        case .always: return true
        case .day: return !configuration.isNight(at: date)
        case .night: return configuration.isNight(at: date)
        }
    }

    /// Readings from the last `readingFreshnessWindow + rateWindow`, newest
    /// first, enough for the latest-reading gate and the fall rate.
    /// Async fetch matching Trio's standard Core Data pattern — never blocks
    /// the caller's thread, never lets a `GlucoseStored` managed object cross
    /// queue boundaries (would otherwise trip
    /// `_PFAssertSafeMultiThreadedAccess_impl`).
    private func fetchRecentReadings() async -> [(date: Date, glucose: Decimal, isManual: Bool)] {
        let cutoff = Date().addingTimeInterval(-(Self.readingFreshnessWindow + Self.rateWindow))
        let predicate = NSPredicate(format: "date >= %@", cutoff as NSDate)
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "GlucoseAlertCoordinator.fetchRecentReadings"
        do {
            let results = try await CoreDataStack.shared.fetchEntitiesAsync(
                ofType: GlucoseStored.self,
                onContext: context,
                predicate: predicate,
                key: "date",
                ascending: false
            )
            return await context.perform {
                ((results as? [GlucoseStored]) ?? []).compactMap { reading in
                    guard let date = reading.date else { return nil }
                    return (date: date, glucose: Decimal(reading.glucose), isManual: reading.isManual)
                }
            }
        } catch {
            warning(.alerts, "Fetching recent glucose for glucose alerts failed", error: error)
            return []
        }
    }
}

extension GlucoseAlertCoordinator: DeterminationObserver {
    func determinationDidUpdate(_ determination: Determination) {
        evaluationQueue.async { [weak self] in
            self?.evaluateForecast(determination)
            self?.evaluateCarbsRequired(determination)
        }
    }
}

extension GlucoseAlertCoordinator: SnoozeObserver {
    /// Global snooze (Snooze module / lock-screen action). Clear all firing
    /// IDs so the post-snooze evaluation can re-fire fresh if any condition
    /// still breaches.
    func snoozeDidChange(_ untilDate: Date) {
        // Mirror the global snooze onto per-alarm snoozedUntil: alarms with
        // "Override Silence & DnD" are issued .critical and pierce the
        // AlertMuter, so the shared mute window alone can't hold them. A
        // shorter per-type snooze (e.g. a 15-min swipe) would otherwise
        // resurface them mid-window. Urgent low keeps its 15-minute safety
        // floor and is never bulk-snoozed. An ended snooze (.distantPast)
        // clears the stamps the same way.
        for type in GlucoseAlertType.allCases where type != .urgentLow {
            snoozeGlucoseType(type, until: untilDate)
        }
        guard untilDate > Date() else { return }
        evaluationQueue.async { [weak self] in
            self?.firingAlertIDs.removeAll()
        }
    }
}

extension GlucoseAlertCoordinator: GlucoseSnoozeObserver {
    /// Per-type snooze from an in-app banner tap / swipe / menu choice.
    /// Stamps `snoozedUntil` on every matching `GlucoseAlert`, retracts every
    /// in-flight alert of that type (so a stacked deck of multiple low
    /// alarms dismisses as one unit), and drops matching entries from
    /// `firingAlertIDs` so the next post-snooze reading evaluates fresh.
    func snoozeGlucoseType(_ type: GlucoseAlertType, until untilDate: Date) {
        DispatchQueue.main.async {
            let store = GlucoseAlertsStore.shared
            var updated = store.alerts
            var matchingAlarms: [GlucoseAlert] = []
            for index in updated.indices where updated[index].type == type {
                updated[index].snoozedUntil = untilDate
                matchingAlarms.append(updated[index])
            }
            guard !matchingAlarms.isEmpty else { return }
            store.alerts = updated
            for alarm in matchingAlarms {
                self.trioAlertManager.retractAlert(identifier: self.alertID(for: alarm))
            }
            let ids = Set(matchingAlarms.map(\.id))
            self.evaluationQueue.async { [weak self] in
                self?.firingAlertIDs.subtract(ids)
            }
        }
    }
}
