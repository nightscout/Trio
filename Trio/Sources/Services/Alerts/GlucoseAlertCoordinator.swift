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

    private let coreDataContext = CoreDataStack.shared.newTaskContext()
    private let evaluationQueue = DispatchQueue(label: "GlucoseAlertCoordinator.queue")
    private var firingAlertIDs: Set<UUID> = []
    private var subscriptions = Set<AnyCancellable>()
    @SyncAccess private var alertsSnapshot: [GlucoseAlert] = []
    @SyncAccess private var configurationSnapshot = GlucoseAlertConfiguration()

    /// 5 mg/dL recovery margin before we retract a fired alert. Prevents flap
    /// at the threshold boundary.
    private static let recoveryMarginMgDL: Decimal = 5

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
        glucoseStorage.updatePublisher
            .receive(on: evaluationQueue)
            .sink { [weak self] _ in self?.evaluateGlucoseAlarms() }
            .store(in: &subscriptions)
    }

    // MARK: - Reading-based evaluation

    private func evaluateGlucoseAlarms() {
        guard !isInLaunchQuietWindow else { return }
        let snapshot = alertsSnapshot
        let configuration = configurationSnapshot
        let now = Date()

        guard let latest = fetchLatestReading() else { return }
        let latestValue = Decimal(latest.glucose)

        // Iterate in type priority order so we can suppress lesser low-family
        // alarms when a more severe one is firing (urgent low > low). Without
        // this, glucose=60 with both urgent-low (54) AND low (70) configured
        // would surface two in-app alerts for the same low event.
        let sorted = snapshot.sorted { $0.type.priority < $1.type.priority }
        var urgentLowFiring = false
        for alarm in sorted where alarm.type != .forecastedLow {
            if alarm.type == .low, urgentLowFiring {
                retractIfFiring(alarm)
                continue
            }
            evaluateReadingBased(alarm, latestMgDL: latestValue, now: now, configuration: configuration)
            if alarm.type == .urgentLow, firingAlertIDs.contains(alarm.id) {
                urgentLowFiring = true
            }
        }
    }

    private func evaluateReadingBased(
        _ alarm: GlucoseAlert,
        latestMgDL: Decimal,
        now: Date,
        configuration: GlucoseAlertConfiguration
    ) {
        guard alarm.shouldEvaluate, !isAlarmSnoozed(alarm, at: now),
              isActive(alarm, at: now, configuration: configuration)
        else {
            retractIfFiring(alarm)
            return
        }

        let breached: Bool
        switch alarm.type {
        case .low,
             .urgentLow:
            breached = latestMgDL <= alarm.thresholdMgDL
        case .high:
            breached = latestMgDL >= alarm.thresholdMgDL
        case .forecastedLow:
            return // handled via determinationDidUpdate
        }

        if breached {
            fireIfNeeded(alarm, valueMgDL: latestMgDL)
        } else if shouldRetract(alarm, latestMgDL: latestMgDL) {
            retractIfFiring(alarm)
        }
    }

    // MARK: - Forecast-based evaluation

    private func evaluateForecast(_ determination: Determination) {
        guard !isInLaunchQuietWindow else { return }
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

    private func shouldRetract(_ alarm: GlucoseAlert, latestMgDL: Decimal) -> Bool {
        dispatchPrecondition(condition: .onQueue(evaluationQueue))
        guard firingAlertIDs.contains(alarm.id) else { return false }
        switch alarm.type {
        case .forecastedLow,
             .low,
             .urgentLow:
            return latestMgDL >= alarm.thresholdMgDL + Self.recoveryMarginMgDL
        case .high:
            return latestMgDL <= alarm.thresholdMgDL - Self.recoveryMarginMgDL
        }
    }

    private func alertID(for alarm: GlucoseAlert) -> Alert.Identifier {
        let typeSlug: String
        switch alarm.type {
        case .urgentLow: typeSlug = "urgentLow"
        case .low: typeSlug = "low"
        case .forecastedLow: typeSlug = "forecastedLow"
        case .high: typeSlug = "high"
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
                format: String(localized: "Glucose %1$@ at or below %2$@."),
                valueString, limitString
            )
        case .forecastedLow:
            return String(
                format: String(localized: "Forecast +%1$d min %2$@, at or below limit %3$@."),
                ForecastedGlucoseEvaluator.defaultHorizonMinutes, valueString, limitString
            )
        case .high:
            return String(
                format: String(localized: "Glucose %1$@ at or above %2$@."),
                valueString, limitString
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

    private func fetchLatestReading() -> GlucoseStored? {
        do {
            let cutoff = Date().addingTimeInterval(-Self.readingFreshnessWindow)
            let predicate = NSPredicate(format: "date >= %@", cutoff as NSDate)
            let results = try CoreDataStack.shared.fetchEntities(
                ofType: GlucoseStored.self,
                onContext: coreDataContext,
                predicate: predicate,
                key: "date",
                ascending: false,
                fetchLimit: 1
            ) as? [GlucoseStored]
            return results?.first
        } catch {
            debug(.service, "GlucoseAlertCoordinator: glucose fetch failed: \(error)")
            return nil
        }
    }
}

extension GlucoseAlertCoordinator: DeterminationObserver {
    func determinationDidUpdate(_ determination: Determination) {
        evaluationQueue.async { [weak self] in
            self?.evaluateForecast(determination)
        }
    }
}
