import Combine
import CoreData
import Foundation
import LoopKit
import LoopKitUI
import LupedSmartwatchKit
import LupedSmartwatchKitUI
import Swinject

/// A watch plugin Trio can host. Trio links its plugins statically.
struct SmartwatchPlugin {
    let managerType: SmartwatchManagerUI.Type
    let descriptor: SmartwatchManagerDescriptor

    static let all: [SmartwatchPlugin] = [
        SmartwatchPlugin(
            managerType: LupedSmartwatchManager.self,
            descriptor: SmartwatchManagerDescriptor(
                identifier: LupedSmartwatchManager.pluginIdentifier,
                localizedTitle: LupedSmartwatchManager.localizedTitle,
                subtitle: "Pebble Time 2 and Pebble Round 2",
                manufacturer: "Core Devices",
                image: LupedSmartwatchManager.onboardingImage
            )
        )
    ]

    static func managerType(for identifier: String) -> SmartwatchManagerUI.Type? {
        all.first { $0.descriptor.identifier == identifier }?.managerType
    }
}

/// Hosts one `SmartwatchManager` plugin (such as the Pebble plugin) next to the
/// Apple Watch and Garmin integrations: keeps it, feeds it Trio's state and
/// glucose alerts, and routes its log lines to the device log.
protocol SmartwatchHost: AnyObject {
    var smartwatchManager: SmartwatchManagerUI? { get }
    /// Fires when a watch manager is added or removed.
    var smartwatchManagerChanged: AnyPublisher<Void, Never> { get }
    var availableSmartwatchManagers: [SmartwatchManagerDescriptor] { get }

    @MainActor func setupViewController(
        for identifier: String,
        completionDelegate: CompletionDelegate?
    ) -> UIViewController?
    @MainActor func settingsViewController(completionDelegate: CompletionDelegate?) -> UIViewController?

    /// Offers a URL Trio doesn't handle itself, such as a companion app's callback.
    @MainActor func handle(_ url: URL) -> Bool
}

final class BaseSmartwatchHost: SmartwatchHost, Injectable {
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var apsManager: APSManager!
    @Injected() private var deviceDataManager: DeviceDataManager!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var iobService: IOBService!
    @Injected() private var trioAlertManager: TrioAlertManager!
    @Injected() private var deviceLogStore: DeviceLogStore!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var adjustmentManager: AdjustmentManager!
    @Injected() private var overrideStorage: OverrideStorage!
    @Injected() private var tempTargetStorage: TempTargetsStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var bolusCalculationManager: BolusCalculationManager!
    @Injected() private var bolusSafetyValidator: BolusSafetyValidator!

    @PersistedProperty(key: "SmartwatchManagerState") private var rawSmartwatchManager: [String: Any]?

    private let changedSubject = PassthroughSubject<Void, Never>()
    private var subscriptions = Set<AnyCancellable>()
    private let coreDataQueue = DispatchQueue(label: "BaseSmartwatchHost.coreData", qos: .utility)

    /// Main-actor state for sending snapshots.
    @MainActor private var lastSentSnapshot: SmartwatchStatusSnapshot?
    @MainActor private var updateGeneration = 0
    /// Hands out the bolus context and tracks the watch bolus being delivered.
    @MainActor private var bolusContextIssuer = SmartwatchBolusContextIssuer()
    /// Carb entries from the watch that the latest determination may not count yet.
    @MainActor private var watchCarbEntries: [WatchCarbEntry] = []
    /// When this host first saw the latest determination: watch carbs stored
    /// before then count as in its COB.
    @MainActor private var determinationSighting = DeterminationSighting()
    /// Glucose alerts the plugin restored from before a relaunch that Trio doesn't issue again.
    @MainActor private var restoredAlerts = RestoredWatchAlerts(launchedAt: Date())

    private(set) var smartwatchManager: SmartwatchManagerUI? {
        didSet {
            smartwatchManager?.smartwatchManagerDelegate = self
            rawSmartwatchManager = smartwatchManager.map(Self.rawValue(of:))
            changedSubject.send()
            Task { @MainActor in self.refresh() }
        }
    }

    var smartwatchManagerChanged: AnyPublisher<Void, Never> { changedSubject.eraseToAnyPublisher() }

    var availableSmartwatchManagers: [SmartwatchManagerDescriptor] { SmartwatchPlugin.all.map(\.descriptor) }

    init(resolver: Resolver) {
        injectServices(resolver)
        restoreManager()
        trioAlertManager.addAlertForwarder(self)
        broadcaster.register(SettingsObserver.self, observer: self)
        subscribeToUpdates()
    }

    // MARK: - Persistence

    private static func rawValue(of manager: SmartwatchManager) -> [String: Any] {
        ["managerIdentifier": manager.pluginIdentifier, "state": manager.rawState]
    }

    private func restoreManager() {
        guard let raw = rawSmartwatchManager else { return }
        guard let identifier = raw["managerIdentifier"] as? String,
              let state = raw["state"] as? SmartwatchManager.RawStateValue,
              let managerType = SmartwatchPlugin.managerType(for: identifier),
              let manager = managerType.init(rawState: state)
        else {
            // As for the pump and CGM: keep the saved state for a build that has the plugin.
            warning(.watch, "Saved watch manager unavailable; keeping its state for a later launch")
            return
        }
        manager.smartwatchManagerDelegate = self
        smartwatchManager = manager
    }

    // MARK: - Setup and settings

    @MainActor func setupViewController(
        for identifier: String,
        completionDelegate: CompletionDelegate?
    ) -> UIViewController? {
        guard let managerType = SmartwatchPlugin.managerType(for: identifier) else { return nil }
        let result = managerType.setupViewController(
            bluetoothProvider: deviceDataManager.bluetoothManager,
            displayGlucosePreference: displayGlucosePreference(),
            colorPalette: .default,
            allowDebugFeatures: false
        )
        switch result {
        case var .userInteractionRequired(viewController):
            viewController.smartwatchManagerOnboardingDelegate = self
            viewController.completionDelegate = completionDelegate
            return viewController
        case let .createdAndOnboarded(manager):
            smartwatchManagerOnboarding(didCreateSmartwatchManager: manager)
            smartwatchManagerOnboarding(didOnboardSmartwatchManager: manager)
            return nil
        }
    }

    @MainActor func settingsViewController(completionDelegate: CompletionDelegate?) -> UIViewController? {
        guard let manager = smartwatchManager else { return nil }
        var viewController = manager.settingsViewController(
            bluetoothProvider: deviceDataManager.bluetoothManager,
            displayGlucosePreference: displayGlucosePreference(),
            colorPalette: .default,
            allowDebugFeatures: false
        )
        viewController.completionDelegate = completionDelegate
        return viewController
    }

    private func displayGlucosePreference() -> DisplayGlucosePreference {
        DisplayGlucosePreference(
            displayGlucoseUnit: settingsManager.settings
                .units == .mmolL ? .millimolesPerLiter : .milligramsPerDeciliter
        )
    }

    @MainActor func handle(_ url: URL) -> Bool {
        smartwatchManager?.watchHostDidReceiveURL(url) ?? false
    }

    // MARK: - Snapshots

    private func subscribeToUpdates() {
        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.update()
                    self?.clearRestoredAlertsIfDue()
                }
            }
            .store(in: &subscriptions)

        CoreDataStack.shared.entityChangePublisher
            .receive(on: coreDataQueue)
            .filteredByEntityName("GlucoseStored")
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
            .store(in: &subscriptions)

        CoreDataStack.shared.entityChangePublisher
            .receive(on: coreDataQueue)
            .filteredByEntityName("OrefDetermination")
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
            .store(in: &subscriptions)

        iobService.iobPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
            .store(in: &subscriptions)

        apsManager.lastLoopDateSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
            .store(in: &subscriptions)

        // The toggles write UserDefaults directly; resend only when the permitted set changes.
        Foundation.NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in UserDefaults.standard.permittedSmartwatchActions(within: UserDefaults.smartwatchRemoteActions) }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
            .store(in: &subscriptions)

        for entity in ["OverrideStored", "TempTargetStored"] {
            CoreDataStack.shared.entityChangePublisher
                .receive(on: coreDataQueue)
                .filteredByEntityName(entity)
                .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
                .store(in: &subscriptions)
        }
    }

    /// Sends the current snapshot even if unchanged, for a new watch manager or
    /// one that reconnected.
    @MainActor private func refresh() {
        lastSentSnapshot = nil
        update()
    }

    @MainActor private func update() {
        guard let manager = smartwatchManager else { return }
        updateGeneration += 1
        let generation = updateGeneration
        let capabilities = manager.effectiveCapabilities
        Task { @MainActor in
            let snapshot: SmartwatchStatusSnapshot
            do {
                snapshot = try await makeSnapshot(capabilities: capabilities)
            } catch {
                warning(.watch, "Unable to build the watch snapshot: \(error)")
                return
            }
            guard generation == updateGeneration,
                  let current = smartwatchManager, current === manager,
                  snapshot != lastSentSnapshot
            else { return }
            lastSentSnapshot = snapshot
            current.watchDataDidUpdate(snapshot)
        }
    }

    private struct DeterminationValues {
        /// When it was calculated (`deliverAt`): its IOB counts the insulin delivered
        /// before this (it may count a little more, which only lowers the
        /// recommendation). Its `timestamp` is moved to when it was enacted, after an
        /// SMB it decided on. Carbs are fetched later than `deliverAt`, so watch carbs
        /// are counted by `DeterminationSighting` instead.
        var calculatedAt: Date?
        var cob: Double?
        var eventualGlucose: Double?
        var insulinSensitivity: Double?
        var sensitivityRatio: Double?
        var target: Double?
        var scheduledBasal: Double?
        var minPredBG: Decimal?
    }

    @MainActor private func makeSnapshot(capabilities: SmartwatchCapabilities) async throws -> SmartwatchStatusSnapshot {
        let readings = try await fetchReadings(since: Date().addingTimeInterval(-SmartwatchStatusSnapshot.historyInterval))
        var snapshot = SmartwatchStatusSnapshot(
            displayUnit: settingsManager.settings.units == .mmolL ? .millimolesPerLiter : .milligramsPerDeciliter,
            glucose: readings.last,
            glucoseHistory: capabilities.contains(.history) ? readings : []
        )
        if capabilities.contains(.remoteOverride) {
            snapshot.overridePresets = try await overridePresets()
        }
        if capabilities.contains(.remoteTempTarget) {
            snapshot.tempTargetPresets = try await tempTargetPresets()
        }
        addRemoteActionInfo(to: &snapshot, capabilities: capabilities)
        guard capabilities.contains(.loopStatus) || capabilities.contains(.therapy) || capabilities.contains(.remoteBolus)
        else { return snapshot }

        let determination = try await latestDetermination()
        if capabilities.contains(.remoteBolus) {
            snapshot.bolusContext = await currentBolusContext(
                minPredBG: determination?.minPredBG,
                determinationCalculatedAt: determination?.calculatedAt,
                latestGlucoseDate: readings.last?.date
            )
        }
        if capabilities.contains(.loopStatus) {
            snapshot.insulinOnBoard = iobService.currentIOB.map { Double(truncating: $0 as NSDecimalNumber) }
            snapshot.carbsOnBoard = determination?.cob
            let lastLoop = apsManager.lastLoopDate
            snapshot.lastLoopCompleted = lastLoop == .distantPast ? nil : lastLoop
            snapshot.isClosedLoop = settingsManager.settings.dosingMode == .closed
        }
        if capabilities.contains(.therapy) {
            var tempBasalRate: Double?
            if case let .tempBasal(dose) = deviceDataManager.pumpManager?.status.basalDeliveryState {
                tempBasalRate = dose.unitsPerHour
            }
            snapshot.therapy = SmartwatchTherapyContext(
                tempBasalRate: tempBasalRate,
                scheduledBasalRate: determination?.scheduledBasal,
                insulinSensitivity: determination?.insulinSensitivity,
                eventualGlucose: determination?.eventualGlucose,
                sensitivityRatio: determination?.sensitivityRatio,
                // The target the algorithm used, including any override or temp target.
                correctionRange: determination?.target.map { $0 ... $0 }
            )
        }
        return snapshot
    }

    /// What every snapshot carries for the remote actions: the user's permissions
    /// and the limits a watch shows before it has a bolus context.
    @MainActor private func addRemoteActionInfo(
        to snapshot: inout SmartwatchStatusSnapshot,
        capabilities: SmartwatchCapabilities
    ) {
        snapshot.permittedActions = UserDefaults.standard.permittedSmartwatchActions(within: capabilities)
        // oref has no per-entry carb absorption, so a watch needn't ask for one.
        snapshot.usesCarbAbsorption = false
        if capabilities.contains(.remoteCarbs) {
            snapshot.maximumCarbEntry = Double(truncating: settingsManager.settings.maxCarbs as NSNumber)
        }
        if capabilities.contains(.remoteBolus) {
            snapshot.bolusIncrement = SmartwatchStatusSnapshot
                .bolusIncrement(of: deviceDataManager.pumpManager?.supportedBolusVolumes ?? [])
        }
    }

    private func fetchReadings(since start: Date) async throws -> [SmartwatchGlucoseReading] {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "smartwatchReadings"
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate(format: "date >= %@", start as NSDate),
            key: "date",
            ascending: true,
            fetchLimit: 0
        )
        return await context.perform {
            (results as? [GlucoseStored] ?? []).compactMap { stored in
                guard let date = stored.date else { return nil }
                return SmartwatchGlucoseReading(
                    date: date,
                    milligramsPerDeciliter: Double(stored.glucose),
                    trend: stored.direction.flatMap { BloodGlucose.Direction(from: $0) }?.smartwatchTrend,
                    wasUserEntered: stored.isManual
                )
            }
        }
    }

    // MARK: - Watch bolus

    /// The recommendation Trio's Apple Watch app shows, counting carbs the watch
    /// just added as that app counts the carbs it is about to save: the plugin adds
    /// the carbs of a carbs-and-bolus request first and checks the bolus against
    /// the next snapshot, before a new determination has counted them in COB.
    @MainActor private func currentBolusContext(
        minPredBG: Decimal?,
        determinationCalculatedAt: Date?,
        latestGlucoseDate: Date?
    ) async -> SmartwatchBolusContext {
        let now = Date()
        let countedBefore = determinationSighting.seenAt(calculatedAt: determinationCalculatedAt, now: now)
        watchCarbEntries = Self.uncountedWatchCarbs(watchCarbEntries, determinationDate: countedBefore, now: now)
        let result = await bolusCalculationManager.handleBolusCalculation(
            carbs: Decimal(watchCarbEntries.reduce(0) { $0 + $1.grams }),
            useFattyMealCorrection: false,
            useSuperBolus: false,
            lastLoopDate: apsManager.lastLoopDate,
            minPredBG: minPredBG ?? 54,
            simulatedCOB: nil,
            isBackdated: false
        )
        let deliveredSince = await insulinDelivered(since: determinationCalculatedAt)
        let inputs = SmartwatchBolusContextIssuer.Inputs(
            recommendedBolus: Self.watchRecommendation(
                calculated: Double(truncating: result.insulinCalculated as NSNumber),
                deliveredSinceDetermination: deliveredSince
            ),
            maximumBolus: Double(truncating: settingsManager.pumpSettings.maxBolus as NSNumber),
            supportedBolusVolumes: deviceDataManager.pumpManager?.supportedBolusVolumes ?? [],
            latestGlucoseDate: latestGlucoseDate
        )
        return bolusContextIssuer.context(for: inputs, now: Date())
    }

    /// Delivers a bolus the plugin authenticated, if LoopKit's `SmartwatchBolusPolicy`
    /// allows it, through the same path as Trio's Apple Watch app.
    @MainActor private func handleBolusRequest(
        _ request: SmartwatchBolusRequest,
        from manager: SmartwatchManager
    ) async throws -> Double {
        log(manager, .receive, String(
            format: "%@ request: %.3f U, confirmed at %@, context %@",
            request.isForced ? "Forced bolus (recommendation not checked)" : "Bolus",
            request.units,
            String(describing: request.requestedAt),
            request.contextToken.uuidString
        ))
        if bolusContextIssuer.isDelivering(request) {
            log(manager, .error, "Bolus request answered with inProgress: the same bolus is still being delivered")
            throw SmartwatchBolusError.inProgress
        }
        let refusal = refusal(for: manager, capability: .remoteBolus, isAllowed: UserDefaults.standard.allowSmartwatchBolus)
        let pumpManager = deviceDataManager.pumpManager
        let latestGlucoseDate = try? await fetchReadings(since: Date().addingTimeInterval(-60 * 60)).last?.date
        let policy = SmartwatchBolusPolicy(
            limits: manager.remoteActionLimits.bolusPolicyLimits,
            isAllowed: refusal == nil,
            currentContext: bolusContextIssuer.current,
            latestGlucoseDate: latestGlucoseDate,
            recentDeliveries: UserDefaults.standard.smartwatchBolusDeliveries,
            roundToSupportedVolume: { pumpManager?.roundToSupportedBolusVolume(units: $0) ?? $0 }
        )
        let units: Double
        switch policy.evaluate(request, now: Date()) {
        case let .failure(error):
            let reason = switch error {
            case .notAllowed: " (\(refusal ?? ""))"
            case .noRecentGlucose: latestGlucoseDate.map {
                    String(format: " (newest glucose %.0f min ago)", Date().timeIntervalSince($0) / 60)
                } ?? " (no glucose in the last hour)"
            default: ""
            }
            log(manager, .error, "Bolus request rejected: \(error)\(reason)")
            throw error
        case let .success(allowed):
            units = allowed
        }

        // Spent before the checks below, so a resend that arrives while they run
        // gets inProgress instead of passing the policy again.
        bolusContextIssuer.beginDelivery(of: request)
        defer { bolusContextIssuer.endDelivery() }

        // Trio's bolus safety checks for max bolus and max IOB. Their recent-bolus
        // check (20 % within 6 minutes) is for remote commands and Shortcuts, which
        // can arrive late or twice from someone who can't see what was just given;
        // like Trio's Apple Watch app, a watch bolus goes without it: it was
        // confirmed on the watch at most 30 s ago, is one per 5 minutes, is capped
        // at a recommendation that counts insulin given since the determination,
        // and a resend during delivery gets inProgress. With it, a small bolus for
        // more carbs was refused after almost every SMB. A window starting now
        // leaves that check nothing to count.
        do {
            if case let .rejected(reason) = try await bolusSafetyValidator
                .validate(bolusAmount: Decimal(units), lookbackStart: Date())
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

        // Checked again after the awaits above, right before the pump call, so a
        // permission turned off meanwhile stops the bolus.
        if let refusal = self.refusal(
            for: manager,
            capability: .remoteBolus,
            isAllowed: UserDefaults.standard.allowSmartwatchBolus
        ) {
            log(manager, .error, "Bolus request rejected just before delivery: notAllowed (\(refusal))")
            throw SmartwatchBolusError.notAllowed
        }
        log(manager, .delegate, String(format: "Delivering watch bolus of %.3f U", units))

        // Counted for the time between watch boluses from here, whether or not the
        // pump reports it delivered: a failure can be uncertain (the pump lost
        // contact mid-bolus), and a resend at once could give it twice. Only a
        // delivered bolus counts toward the daily total.
        let attemptedAt = Date()
        UserDefaults.standard.smartwatchBolusDeliveries = Self.bolusAttempted(
            at: attemptedAt,
            in: UserDefaults.standard.smartwatchBolusDeliveries
        )

        // enactBolus answers through its callback before it returns.
        let outcome = BolusOutcome()
        await apsManager.enactBolus(amount: units, isSMB: false) { success, message in
            outcome.success = success
            outcome.message = message
        }
        guard outcome.success else {
            log(manager, .error, "Watch bolus delivery failed: \(outcome.message)")
            refresh()
            throw SmartwatchBolusError.deliveryFailed(outcome.message)
        }
        UserDefaults.standard.smartwatchBolusDeliveries = Self.bolusDelivered(
            units,
            attemptedAt: attemptedAt,
            in: UserDefaults.standard.smartwatchBolusDeliveries
        )
        log(manager, .delegateResponse, String(format: "Watch bolus of %.3f U delivered", units))
        refresh()
        return units
    }

    struct WatchCarbEntry: Equatable {
        let date: Date
        let grams: Double
    }

    /// The watch carb entries a determination doesn't count yet: those stored after
    /// `determinationDate`, when this host first saw it (`DeterminationSighting`).
    /// Entries over 30 minutes old are dropped too, so carbs are never counted
    /// twice and old ones don't raise the recommendation; both mistakes only lower it.
    ///
    /// Not `deliverAt`: Trio takes it before the determination fetches its carbs,
    /// so carbs stored in between are in its COB and were added again.
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

    /// The watch boluses `SmartwatchBolusPolicy` counts, with an attempt at `date`:
    /// 0 U, so it counts for the time between boluses but not the daily total.
    static func bolusAttempted(
        at date: Date,
        in deliveries: [SmartwatchBolusPolicy.Delivery]
    ) -> [SmartwatchBolusPolicy.Delivery] {
        deliveries + [SmartwatchBolusPolicy.Delivery(date: date, units: 0)]
    }

    /// The attempt at `attemptedAt` delivered `units`: they count toward the daily total too.
    static func bolusDelivered(
        _ units: Double,
        attemptedAt: Date,
        in deliveries: [SmartwatchBolusPolicy.Delivery]
    ) -> [SmartwatchBolusPolicy.Delivery] {
        deliveries.filter { $0 != SmartwatchBolusPolicy.Delivery(date: attemptedAt, units: 0) }
            + [SmartwatchBolusPolicy.Delivery(date: attemptedAt, units: units)]
    }

    /// The watch's error for a rejection by Trio's bolus safety checks, so the
    /// plugin can tell the watch why (too soon, over the maximum bolus).
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

    private final class BolusOutcome: @unchecked Sendable {
        var success = false
        var message = "no answer from the pump"
    }

    /// Trio's override presets; `enabled` marks the running one. Durations are stored in minutes.
    private func overridePresets() async throws -> [SmartwatchPreset] {
        let ids = try await overrideStorage.fetchForOverridePresets()
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "smartwatchOverridePresets"
        let rows: [OverrideStored] = try await CoreDataStack.shared.getNSManagedObject(with: ids, context: context)
        return await context.perform {
            rows.compactMap { row in
                guard let id = row.id, let name = row.name else { return nil }
                let minutes = row.duration.map { Double(truncating: $0) } ?? 0
                return SmartwatchPreset(
                    id: id,
                    name: name,
                    isActive: row.enabled,
                    duration: row.indefinite || minutes <= 0 ? nil : minutes * 60
                )
            }
        }
    }

    /// Trio's temp target presets; `enabled` marks the running one. Durations are stored in minutes.
    private func tempTargetPresets() async throws -> [SmartwatchPreset] {
        let ids = try await tempTargetStorage.fetchForTempTargetPresets()
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "smartwatchTempTargetPresets"
        let rows: [TempTargetStored] = try await CoreDataStack.shared.getNSManagedObject(with: ids, context: context)
        return await context.perform {
            rows.compactMap { row in
                guard let id = row.id, let name = row.name else { return nil }
                let minutes = row.duration.map { Double(truncating: $0) } ?? 0
                return SmartwatchPreset(
                    id: id.uuidString,
                    name: name,
                    isActive: row.enabled,
                    duration: minutes > 0 ? minutes * 60 : nil
                )
            }
        }
    }

    /// The newest determination from the last 30 minutes, enacted or suggested.
    private func latestDetermination() async throws -> DeterminationValues? {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "smartwatchDetermination"
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: context,
            predicate: NSPredicate.predicateFor30MinAgoForDetermination,
            key: "deliverAt",
            ascending: false,
            fetchLimit: 1
        )
        return await context.perform {
            guard let determination = (results as? [OrefDetermination])?.first else { return nil }
            let double = { (value: NSDecimalNumber?) in value.map { Double(truncating: $0) } }
            return DeterminationValues(
                calculatedAt: determination.deliverAt,
                cob: Double(determination.cob),
                eventualGlucose: double(determination.eventualBG),
                insulinSensitivity: double(determination.insulinSensitivity),
                sensitivityRatio: double(determination.sensitivityRatio),
                target: double(determination.currentTarget),
                scheduledBasal: double(determination.scheduledBasal),
                minPredBG: determination.minPredBGFromReason
            )
        }
    }

    // MARK: - Device log

    private func log(_ manager: SmartwatchManager, _ type: DeviceLogEntryType, _ message: String, device: String? = nil) {
        deviceLogStore.log(managerIdentifier: manager.pluginIdentifier, deviceIdentifier: device, type: type, message: message)
    }
}

// MARK: - SettingsObserver

extension BaseSmartwatchHost: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        // Units or dosing mode may have changed; unchanged snapshots aren't resent.
        Task { @MainActor in self.update() }
    }
}

// MARK: - Restored watch alerts

extension BaseSmartwatchHost {
    /// When to clear glucose alerts the plugin restored from before a relaunch.
    /// Trio keeps which alarms are firing in memory only: after a relaunch it
    /// issues an alarm that still applies again once its launch quiet window is
    /// over, but never retracts one that ended while it wasn't running. So the
    /// host waits for a glucose update after the quiet window, and one at least a
    /// minute after that, then retracts every glucose alarm it hasn't forwarded
    /// since launch. The plugin ignores alerts it doesn't have.
    struct RestoredWatchAlerts {
        /// `GlucoseAlertCoordinator`'s launch quiet window.
        static let launchQuietWindow: TimeInterval = 30
        /// Time Trio gets after its first update to issue again what still applies.
        static let reissueTime: TimeInterval = 60

        let launchedAt: Date
        /// Glucose alerts forwarded since launch and not retracted.
        var forwarded: Set<String> = []
        private(set) var isCleared = false
        private var firstUpdateAfterQuietWindow: Date?

        init(launchedAt: Date) {
            self.launchedAt = launchedAt
        }

        /// Called on each glucose update; true once, when it's time to clear.
        mutating func glucoseDidUpdate(at now: Date) -> Bool {
            guard !isCleared, now.timeIntervalSince(launchedAt) >= Self.launchQuietWindow else { return false }
            guard let first = firstUpdateAfterQuietWindow else {
                firstUpdateAfterQuietWindow = now
                return false
            }
            guard now.timeIntervalSince(first) >= Self.reissueTime else { return false }
            isCleared = true
            return true
        }

        /// Of the glucose alarms' alerts, those to retract: the ones not forwarded since launch.
        func toRetract(alarmAlerts: [String]) -> [String] {
            alarmAlerts.filter { !forwarded.contains($0) }
        }
    }

    @MainActor private func clearRestoredAlertsIfDue() {
        guard let manager = smartwatchManager,
              type(of: manager).capabilities.contains(.alerts),
              restoredAlerts.glucoseDidUpdate(at: Date())
        else { return }
        let alarmAlerts = GlucoseAlertsStore.shared.alerts
            .map { GlucoseAlertCoordinator.alertID(for: $0) }
            .filter { Self.glucoseAlertType(of: $0) != nil }
            .map(\.value)
        for identifier in restoredAlerts.toRetract(alarmAlerts: alarmAlerts) {
            manager.watchAlertDidRetract(SmartwatchAlertIdentifier(identifier))
        }
    }
}

// MARK: - TrioAlertForwarder

extension BaseSmartwatchHost: TrioAlertForwarder {
    /// Which glucose alert this is: Trio's glucose alerts are
    /// `Trio.glucose.<type>.<UUID>`. Carbs-required and every other alert are nil.
    static func glucoseAlertType(of identifier: Alert.Identifier) -> SmartwatchGlucoseAlertType? {
        guard identifier.managerIdentifier == BaseTrioAlertManager.managerIdentifier else { return nil }
        let parts = identifier.alertIdentifier.split(separator: ".")
        guard parts.count >= 2, parts[0] == "glucose" else { return nil }
        switch parts[1] {
        case "urgentLow": return .urgentLow
        case "low": return .low
        case "high": return .high
        case "forecastedLow": return .predictedLow
        default: return nil
        }
    }

    /// Forwards Trio's immediate glucose alerts. Trio's mute drops non-critical
    /// alerts before they get here, so critical ones reach the watch while muted,
    /// as they reach the phone.
    func alertManager(didIssue alert: Alert, muted _: Bool) {
        guard let manager = smartwatchManager, manager.effectiveCapabilities.contains(.alerts) else { return }
        // Trio hands every alert to its forwarders; the watch only gets glucose
        // alerts as they fire. Others (and scheduled ones, such as the not-looping
        // ladder Trio re-arms on every loop) are dropped without a log line.
        guard let glucoseAlertType = Self.glucoseAlertType(of: alert.identifier) else { return }
        guard case .immediate = alert.trigger else {
            log(manager, .delegate, "\(alert.identifier.alertIdentifier) not sent to the watch: a scheduled glucose alert")
            return
        }
        let content = alert.foregroundContent ?? alert.backgroundContent
        let level: SmartwatchAlertLevel = switch alert.interruptionLevel {
        case .active: .informational
        case .timeSensitive: .warning
        case .critical: .critical
        }
        let watchAlert = SmartwatchAlert(
            identifier: SmartwatchAlertIdentifier(alert.identifier.value),
            level: level,
            title: content.title,
            body: content.body,
            issuedAt: Date(),
            glucoseAlertType: glucoseAlertType
        )
        Task { @MainActor in
            self.restoredAlerts.forwarded.insert(watchAlert.identifier.value)
            manager.watchAlertDidIssue(watchAlert)
        }
    }

    func alertManager(didRetract identifier: Alert.Identifier) {
        guard let manager = smartwatchManager,
              type(of: manager).capabilities.contains(.alerts),
              Self.glucoseAlertType(of: identifier) != nil
        else { return }
        Task { @MainActor in
            self.restoredAlerts.forwarded.remove(identifier.value)
            manager.watchAlertDidRetract(SmartwatchAlertIdentifier(identifier.value))
        }
    }
}

// MARK: - SmartwatchManagerDelegate

extension BaseSmartwatchHost: SmartwatchManagerDelegate {
    func smartwatchManagerDidUpdateState(_ manager: SmartwatchManager) {
        rawSmartwatchManager = Self.rawValue(of: manager)
    }

    func smartwatchManagerWantsDeletion(_ manager: SmartwatchManager) async {
        await MainActor.run {
            debug(.watch, "Watch manager \(manager.pluginIdentifier) wants deletion")
            UserDefaults.standard.resetSmartwatchPermissions()
            smartwatchManager = nil
        }
    }

    func smartwatchManagerRequestsRefresh(_: SmartwatchManager) {
        Task { @MainActor in self.refresh() }
    }

    func smartwatchManager(_ manager: SmartwatchManager, didLogEvent event: SmartwatchDeviceLogEntry) {
        log(manager, DeviceLogEntryType(event.type), event.message, device: event.deviceIdentifier)
    }

    /// Shows the plugin's alert about the watch as Trio's own alert from this
    /// plugin. A plugin can't raise a critical alert: at most time-sensitive.
    func smartwatchManager(_ manager: SmartwatchManager, issueDeviceAlert alert: SmartwatchDeviceAlert) {
        let trioAlert = Alert(
            alert,
            from: manager,
            acknowledgeActionButtonLabel: String(localized: "OK", comment: "Button to acknowledge an alert from a watch plugin")
        )
        log(manager, .error, "Watch plugin alert: \(alert.title): \(alert.body)", device: nil)
        trioAlertManager.issueAlert(trioAlert)
    }

    func smartwatchManager(_ manager: SmartwatchManager, retractDeviceAlert identifier: SmartwatchAlertIdentifier) {
        trioAlertManager.retractAlert(identifier: Alert.Identifier(identifier, from: manager))
    }

    func smartwatchManager(_ manager: SmartwatchManager, requestBolus request: SmartwatchBolusRequest) async throws -> Double {
        try await handleBolusRequest(request, from: manager)
    }

    /// What Trio would recommend with the carbs the user is about to add from the
    /// watch (0 for none), without adding them: Trio's bolus calculator, as for
    /// its Apple Watch app, with those carbs and any watch carbs no determination
    /// has counted yet. Only while boluses from the watch are allowed and glucose
    /// is recent; the bolus itself is checked again after the carbs are added.
    func smartwatchManager(
        _ manager: SmartwatchManager,
        recommendBolusFor request: SmartwatchBolusRecommendationRequest
    ) async throws -> SmartwatchBolusRecommendation {
        try await handleBolusRecommendationRequest(request, from: manager)
    }

    @MainActor private func handleBolusRecommendationRequest(
        _ request: SmartwatchBolusRecommendationRequest,
        from manager: SmartwatchManager
    ) async throws -> SmartwatchBolusRecommendation {
        let grams = request.grams
        log(manager, .receive, String(format: "Bolus recommendation request with %.0f g of carbs", grams))
        if let refusal = refusal(for: manager, capability: .remoteBolus, isAllowed: UserDefaults.standard.allowSmartwatchBolus) {
            log(manager, .error, "Bolus recommendation refused: \(refusal)")
            throw SmartwatchBolusError.notAllowed
        }
        let maximumGlucoseAge = manager.remoteActionLimits.bolusPolicyLimits.maximumGlucoseAge
        guard (try? await fetchReadings(since: Date().addingTimeInterval(-maximumGlucoseAge)).last) != nil else {
            log(manager, .error, "Bolus recommendation refused: no glucose in the last \(Int(maximumGlucoseAge / 60)) minutes")
            throw SmartwatchBolusError.noRecentGlucose
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
        if deliveredSince > 0 {
            log(manager, .delegateResponse, String(
                format: "Bolus recommendation: %.2f U less %.2f U delivered since the determination it uses",
                calculated,
                deliveredSince
            ))
        }
        // Rounded as the bolus check rounds the recommendation it caps at.
        let units = deviceDataManager.pumpManager?.roundToSupportedBolusVolume(units: recommended) ?? recommended
        let maximumBolus = Double(truncating: settingsManager.pumpSettings.maxBolus as NSNumber)
        log(manager, .delegateResponse, String(
            format: "Bolus recommendation with %.0f g of carbs: %.2f U (Max Bolus %.2f U)",
            grams,
            units,
            maximumBolus
        ))
        return SmartwatchBolusRecommendation(units: units, grams: grams, maximumBolus: maximumBolus, issuedAt: Date())
    }

    /// The longest mute a watch can ask for.
    static let maximumMuteDuration: TimeInterval = 4 * 60 * 60

    /// Snoozes Trio's alerts like every other snooze surface, for at most 4 hours;
    /// a duration of 0 ends the snooze. Critical alerts still sound, as for any snooze.
    func smartwatchManager(
        _ manager: SmartwatchManager,
        requestAlertMute request: SmartwatchAlertMuteRequest
    ) async throws -> Date {
        let duration = request.duration
        log(manager, .receive, String(format: "Mute request: %.0f min", duration / 60))
        if let refusal = refusal(for: manager, capability: .remoteMute, isAllowed: UserDefaults.standard.allowSmartwatchMute) {
            log(manager, .error, "Mute request rejected: notAllowed (\(refusal))")
            throw SmartwatchAlertMuteError.notAllowed
        }
        guard manager.remoteActionLimits.requestWindow.contains(request.requestedAt, now: Date()) else {
            log(
                manager,
                .error,
                String(
                    format: "Mute request rejected: expiredRequest (confirmed %.0f s ago)",
                    Date().timeIntervalSince(request.requestedAt)
                )
            )
            throw SmartwatchAlertMuteError.expiredRequest
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

    /// Adds a carb entry like a remote meal, if LoopKit's `SmartwatchCarbEntryPolicy`
    /// allows it, within Max Carbs.
    func smartwatchManager(
        _ manager: SmartwatchManager,
        requestCarbEntry request: SmartwatchCarbEntryRequest
    ) async throws -> Double {
        let grams = request.grams
        log(
            manager,
            .receive,
            String(format: "Carb entry request: %.0f g, confirmed at %@", grams, String(describing: request.requestedAt))
                // Trio's carb model has no per-entry absorption time, so a watch's
                // fast, medium or slow is only logged.
                + (request.absorption.map { ", \($0.rawValue) absorption (not used by Trio)" } ?? "")
        )
        let refusal = refusal(for: manager, capability: .remoteCarbs, isAllowed: UserDefaults.standard.allowSmartwatchCarbs)
        let maxCarbs = Double(truncating: settingsManager.settings.maxCarbs as NSNumber)
        // Check and take the rate-limit slot together, before storing, so a resend
        // that arrives meanwhile is rate limited instead of added twice.
        let outcome: (Result<Double, SmartwatchCarbEntryError>, Date?) = await MainActor.run {
            let previous = UserDefaults.standard.lastSmartwatchCarbEntry
            let policy = SmartwatchCarbEntryPolicy(
                limits: manager.remoteActionLimits.carbEntryPolicyLimits,
                isAllowed: refusal == nil, maximumGrams: maxCarbs, lastEntry: previous
            )
            let result = policy.evaluate(request, now: Date())
            if case .success = result {
                UserDefaults.standard.lastSmartwatchCarbEntry = Date()
            }
            return (result, previous)
        }
        let previousEntry = outcome.1
        if case let .failure(error) = outcome.0 {
            log(manager, .error, "Carb entry request rejected: \(error)\(refusal.map { " (\($0))" } ?? "")")
            throw error
        }
        // Checked again after the hop above, right before storing.
        if let refusal = self.refusal(
            for: manager,
            capability: .remoteCarbs,
            isAllowed: UserDefaults.standard.allowSmartwatchCarbs
        ) {
            await MainActor.run { UserDefaults.standard.lastSmartwatchCarbEntry = previousEntry }
            log(manager, .error, "Carb entry request rejected just before storing: notAllowed (\(refusal))")
            throw SmartwatchCarbEntryError.notAllowed
        }
        do {
            // Dated when the user confirmed it on the watch.
            let entry = carbsStorage.makeCarbEntry(carbs: Decimal(grams), date: request.requestedAt)
            try await carbsStorage.storeCarbs([entry], areFetchedFromRemote: false)
            // Counted from when it was stored: a determination from before then can't include it.
            let storedAt = Date()
            await MainActor.run { self.watchCarbEntries.append(WatchCarbEntry(date: storedAt, grams: grams)) }
        } catch {
            await MainActor.run {
                UserDefaults.standard.lastSmartwatchCarbEntry = previousEntry
            }
            log(manager, .error, "Watch carb entry failed: \(error)")
            throw SmartwatchCarbEntryError.failed(String(describing: error))
        }
        log(manager, .delegateResponse, String(format: "Watch carb entry of %.0f g added", grams))
        Task { @MainActor in self.refresh() }
        return grams
    }

    /// Why a remote action from this watch isn't allowed, or nil when it is.
    private func refusal(for manager: SmartwatchManager, capability: SmartwatchCapabilities, isAllowed: Bool) -> String? {
        let isCurrentWatch = smartwatchManager.map { ($0 as AnyObject) === (manager as AnyObject) } ?? false
        if !isCurrentWatch {
            return "the request isn't from the current watch"
        } else if !manager.effectiveCapabilities.contains(capability) {
            return "this watch doesn't declare \(capability)"
        } else if !isAllowed {
            return "it isn't allowed in the Watch settings"
        }
        return nil
    }

    func smartwatchManager(_ manager: SmartwatchManager, requestOverride request: SmartwatchOverrideRequest) async throws {
        try await handlePresetRequest(
            kind: "Override",
            action: request.action,
            requestedAt: request.requestedAt,
            capability: .remoteOverride,
            isAllowed: UserDefaults.standard.allowSmartwatchOverrides,
            from: manager,
            activate: { try await self.adjustmentManager.activateOverride(.presetID($0), source: .watch) },
            cancel: { try await self.adjustmentManager.cancelOverride(source: .watch) }
        )
    }

    func smartwatchManager(_ manager: SmartwatchManager, requestTempTarget request: SmartwatchTempTargetRequest) async throws {
        try await handlePresetRequest(
            kind: "Temp target",
            action: request.action,
            requestedAt: request.requestedAt,
            capability: .remoteTempTarget,
            isAllowed: UserDefaults.standard.allowSmartwatchTempTargets,
            from: manager,
            activate: { try await self.adjustmentManager.activateTempTarget(.presetID($0), source: .watch) },
            cancel: { try await self.adjustmentManager.cancelTempTarget(source: .watch) }
        )
    }

    /// Starts or ends a preset through the same path as Trio's Apple Watch app, only
    /// for the current watch, with the capability and the user's permission, and for
    /// requests confirmed in the last 30 seconds.
    private func handlePresetRequest(
        kind: String,
        action: SmartwatchPresetAction,
        requestedAt: Date,
        capability: SmartwatchCapabilities,
        isAllowed: Bool,
        from manager: SmartwatchManager,
        activate: (String) async throws -> AdjustmentOutcome,
        cancel: () async throws -> AdjustmentOutcome
    ) async throws {
        let description = switch action {
        case let .activate(presetID): "start preset \(presetID)"
        case .cancel: "end the running one"
        }
        log(manager, .receive, "\(kind) request: \(description), confirmed at \(requestedAt)")
        if let refusal = refusal(for: manager, capability: capability, isAllowed: isAllowed) {
            log(manager, .error, "\(kind) request rejected: notAllowed (\(refusal))")
            throw SmartwatchPresetError.notAllowed
        }
        let age = Date().timeIntervalSince(requestedAt)
        guard manager.remoteActionLimits.requestWindow.contains(requestedAt, now: Date()) else {
            log(manager, .error, String(format: "%@ request rejected: expiredRequest (confirmed %.0f s ago)", kind, age))
            throw SmartwatchPresetError.expiredRequest
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
        Task { @MainActor in self.refresh() }
    }
}

extension UserDefaults {
    /// Whether a watch plugin with `.remoteOverride` may start and end overrides. Off by default.
    static let allowSmartwatchOverridesKey = "Trio.smartwatch.allowOverrides"
    /// Whether a watch plugin with `.remoteTempTarget` may start and end temp targets. Off by default.
    static let allowSmartwatchTempTargetsKey = "Trio.smartwatch.allowTempTargets"
    /// Whether a watch plugin with `.remoteMute` may snooze Trio's alerts. Off by default.
    static let allowSmartwatchMuteKey = "Trio.smartwatch.allowMute"
    /// Whether a watch plugin with `.remoteCarbs` may add carb entries. Off by default.
    static let allowSmartwatchCarbsKey = "Trio.smartwatch.allowCarbs"
    /// Whether a watch plugin with `.remoteBolus` may request boluses. Off by default.
    static let allowSmartwatchBolusKey = "Trio.smartwatch.allowBolus"
    private static let smartwatchBolusDeliveriesKey = "Trio.smartwatch.bolusDeliveries"
    private static let lastSmartwatchCarbEntryKey = "Trio.smartwatch.lastCarbEntry"

    var allowSmartwatchOverrides: Bool { bool(forKey: Self.allowSmartwatchOverridesKey) }
    var allowSmartwatchTempTargets: Bool { bool(forKey: Self.allowSmartwatchTempTargetsKey) }
    var allowSmartwatchMute: Bool { bool(forKey: Self.allowSmartwatchMuteKey) }
    var allowSmartwatchCarbs: Bool { bool(forKey: Self.allowSmartwatchCarbsKey) }
    var allowSmartwatchBolus: Bool { bool(forKey: Self.allowSmartwatchBolusKey) }

    /// Watch boluses delivered in the last 24 hours, kept across launches for the rate limits.
    var smartwatchBolusDeliveries: [SmartwatchBolusPolicy.Delivery] {
        get {
            data(forKey: Self.smartwatchBolusDeliveriesKey)
                .flatMap { try? JSONDecoder().decode([SmartwatchBolusPolicy.Delivery].self, from: $0) } ?? []
        }
        set {
            let dayStart = Date().addingTimeInterval(-24 * 60 * 60)
            set(try? JSONEncoder().encode(newValue.filter { $0.date > dayStart }), forKey: Self.smartwatchBolusDeliveriesKey)
        }
    }

    /// When the last carb entry from the watch was added, for its rate limit.
    var lastSmartwatchCarbEntry: Date? {
        get { object(forKey: Self.lastSmartwatchCarbEntryKey) as? Date }
        set { set(newValue, forKey: Self.lastSmartwatchCarbEntryKey) }
    }

    /// Turns the permissions off, so a new watch plugin never inherits what the
    /// user granted another one.
    /// Every remote action a Watch permission toggle covers.
    static let smartwatchRemoteActions: SmartwatchCapabilities = [
        .remoteBolus, .remoteCarbs, .remoteMute, .remoteOverride, .remoteTempTarget
    ]

    /// The remote actions among `capabilities` whose toggle is on, for the
    /// snapshot's `permittedActions`.
    func permittedSmartwatchActions(within capabilities: SmartwatchCapabilities) -> SmartwatchCapabilities {
        var permitted: SmartwatchCapabilities = []
        if allowSmartwatchBolus { permitted.insert(.remoteBolus) }
        if allowSmartwatchCarbs { permitted.insert(.remoteCarbs) }
        if allowSmartwatchMute { permitted.insert(.remoteMute) }
        if allowSmartwatchOverrides { permitted.insert(.remoteOverride) }
        if allowSmartwatchTempTargets { permitted.insert(.remoteTempTarget) }
        return permitted.intersection(capabilities)
    }

    func resetSmartwatchPermissions() {
        set(false, forKey: Self.allowSmartwatchOverridesKey)
        set(false, forKey: Self.allowSmartwatchTempTargetsKey)
        set(false, forKey: Self.allowSmartwatchMuteKey)
        set(false, forKey: Self.allowSmartwatchCarbsKey)
        set(false, forKey: Self.allowSmartwatchBolusKey)
    }
}

// MARK: - SmartwatchManagerOnboardingDelegate

extension BaseSmartwatchHost: SmartwatchManagerOnboardingDelegate {
    func smartwatchManagerOnboarding(didCreateSmartwatchManager manager: SmartwatchManagerUI) {
        debug(.watch, "Watch manager \(manager.pluginIdentifier) created")
        UserDefaults.standard.resetSmartwatchPermissions()
        smartwatchManager = manager
    }

    func smartwatchManagerOnboarding(didOnboardSmartwatchManager manager: SmartwatchManagerUI) {
        debug(.watch, "Watch manager \(manager.pluginIdentifier) onboarded")
        Task { @MainActor in self.refresh() }
    }
}

extension BloodGlucose.Direction {
    /// The same trend arrow as LoopKit's `GlucoseTrend`.
    var smartwatchTrend: SmartwatchGlucoseTrend? {
        switch self {
        case .doubleUp,
             .tripleUp: .upUpUp
        case .singleUp: .upUp
        case .fortyFiveUp: .up
        case .flat: .flat
        case .fortyFiveDown: .down
        case .singleDown: .downDown
        case .doubleDown,
             .tripleDown: .downDownDown
        case .none,
             .notComputable,
             .rateOutOfRange: nil
        }
    }
}
