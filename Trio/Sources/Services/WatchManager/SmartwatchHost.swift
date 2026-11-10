import Combine
import CoreData
import Foundation
import LoopKit
import LoopKitUI
import LupedSmartwatchKit
import LupedSmartwatchKitUI
import os
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
/// Apple Watch and Garmin integrations: keeps it, tells it when Trio's state
/// changes, answers its reads, forwards Trio's glucose alerts to it, and routes
/// its log lines and alerts to the device log and Trio's alert manager.
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

/// The watch plugin's `SmartwatchManagerDelegate`.
///
/// The plugin reads Trio's state from here after `hostDataDidChange`, which says
/// what changed: a new glucose reading as soon as it is stored, the loop's output
/// when a new determination is saved, and presets, settings or the snooze when
/// they change.
///
/// The plugin's log lines go to the device log, and its alerts to Trio's alert
/// manager, at most time-sensitive. Its remote actions get the checks Trio applies
/// to any request of that kind (`SmartwatchHost+RemoteActions.swift`); whether the
/// watch may ask at all, and how fresh or frequent its requests must be, is the
/// plugin's own setting and policy. Trio's glucose alerts reach the plugin
/// through `SmartwatchHost+AlertForwarder.swift`.
final class BaseSmartwatchHost: SmartwatchHost, Injectable {
    @Injected() var settingsManager: SettingsManager!
    @Injected() var apsManager: APSManager!
    @Injected() var deviceDataManager: DeviceDataManager!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var iobService: IOBService!
    @Injected() var trioAlertManager: TrioAlertManager!
    @Injected() var deviceLogStore: DeviceLogStore!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() var adjustmentManager: AdjustmentManager!
    @Injected() private var overrideStorage: OverrideStorage!
    @Injected() private var tempTargetStorage: TempTargetsStorage!
    @Injected() var carbsStorage: CarbsStorage!
    @Injected() var bolusCalculationManager: BolusCalculationManager!
    @Injected() var bolusSafetyValidator: BolusSafetyValidator!

    @PersistedProperty(key: "SmartwatchManagerState") private var rawSmartwatchManager: [String: Any]?

    private let changedSubject = PassthroughSubject<Void, Never>()
    private var subscriptions = Set<AnyCancellable>()
    private let coreDataQueue = DispatchQueue(label: "BaseSmartwatchHost.coreData", qos: .utility)

    /// What changed since the watch manager was last told, sent on the next main
    /// run loop turn so changes that arrive together go out as one call.
    private lazy var changeBatch = SmartwatchChangeBatch { [weak self] in self?.smartwatchManager }
    /// Whether a watch bolus is being delivered, so a second one gets `inProgress`.
    @MainActor var isDeliveringWatchBolus = false
    /// The answers to the plugin's 0 g recommendation read, which it makes after
    /// every change for its bolus context: logged only when it changes.
    @MainActor var contextRecommendationLog = ContextRecommendationLog()
    /// Carb entries from the watch that the latest determination may not count yet.
    @MainActor var watchCarbEntries: [WatchCarbEntry] = []
    /// When this host first saw the latest determination: watch carbs stored
    /// before then count as in its COB.
    @MainActor var determinationSighting = DeterminationSighting()
    /// Glucose alerts the plugin restored from before a relaunch that Trio doesn't issue again.
    @MainActor var restoredAlerts = RestoredWatchAlerts(launchedAt: Date())

    private(set) var smartwatchManager: SmartwatchManagerUI? {
        didSet {
            if let oldValue, oldValue !== smartwatchManager {
                tearDown(oldValue)
            }
            if let smartwatchManager {
                setUp(smartwatchManager)
            }
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
        broadcaster.register(PumpSettingsObserver.self, observer: self)
        broadcaster.register(SnoozeObserver.self, observer: self)
        subscribeToChanges()
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
        smartwatchManager = manager
    }

    /// A new or restored watch manager: Trio is its delegate, and its alerts can be
    /// acknowledged and given sounds like a pump's or CGM's.
    private func setUp(_ manager: SmartwatchManagerUI) {
        manager.smartwatchManagerDelegate = self
        trioAlertManager.register(responder: manager, for: manager.pluginIdentifier)
        trioAlertManager.register(soundVendor: manager, for: manager.pluginIdentifier)
    }

    /// A removed or replaced watch manager hears nothing more from Trio.
    private func tearDown(_ manager: SmartwatchManagerUI) {
        manager.smartwatchManagerDelegate = nil
        trioAlertManager.unregister(managerIdentifier: manager.pluginIdentifier)
    }

    /// Whether `manager` is the watch manager on the Watch screen. Only its
    /// requests are acted on; a removed one may still hold this host.
    func isCurrentWatch(_ manager: SmartwatchManager) -> Bool {
        smartwatchManager.map { ($0 as AnyObject) === (manager as AnyObject) } ?? false
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
        DisplayGlucosePreference(displayGlucoseUnit: displayUnit)
    }

    private var displayUnit: LoopUnit {
        settingsManager.settings.units == .mmolL ? .millimolesPerLiter : .milligramsPerDeciliter
    }

    @MainActor func handle(_ url: URL) -> Bool {
        smartwatchManager?.watchHostDidReceiveURL(url) ?? false
    }

    // MARK: - Change signals

    private func subscribeToChanges() {
        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.signal(.glucose)
                    self?.clearRestoredAlertsIfDue()
                }
            }
            .store(in: &subscriptions)

        // Also covers readings deleted or entered by hand.
        CoreDataStack.shared.entityChangePublisher
            .receive(on: coreDataQueue)
            .filteredByEntityName("GlucoseStored")
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.signal(.glucose) } }
            .store(in: &subscriptions)

        CoreDataStack.shared.entityChangePublisher
            .receive(on: coreDataQueue)
            .filteredByEntityName("OrefDetermination")
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.determinationDidChange() } }
            .store(in: &subscriptions)

        iobService.iobPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.signal(.loop) } }
            .store(in: &subscriptions)

        apsManager.lastLoopDateSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.signal(.loop) } }
            .store(in: &subscriptions)

        // A manual temp basal starting or ending: Trio enacts nothing while one runs.
        deviceDataManager.manualTempBasal
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.signal(.loop) } }
            .store(in: &subscriptions)

        // A new or removed pump: the bolus volumes the watch rounds to.
        deviceDataManager.pumpDisplayState
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.signal(.settings) } }
            .store(in: &subscriptions)

        for entity in ["OverrideStored", "TempTargetStored"] {
            CoreDataStack.shared.entityChangePublisher
                .receive(on: coreDataQueue)
                .filteredByEntityName(entity)
                .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.signal(.presets) } }
                .store(in: &subscriptions)
        }
    }

    /// Tells the watch manager that everything changed: for a new watch manager,
    /// right after its delegate is set, or one that finished onboarding.
    @MainActor func refresh() {
        changeBatch.discardPending()
        smartwatchManager?.hostDataDidChange(.all)
    }

    /// Tells the watch manager what changed, on the next main run loop turn
    /// together with whatever else changes until then.
    @MainActor func signal(_ changes: SmartwatchHostDataChange) {
        changeBatch.signal(changes)
    }

    /// A new determination: notes when this host first saw it, so the watch carbs
    /// stored before then count as in its COB, then tells the watch.
    @MainActor private func determinationDidChange() {
        guard smartwatchManager != nil else { return }
        Task { @MainActor in
            let determination = try? await latestDetermination()
            _ = determinationSighting.seenAt(calculatedAt: determination?.calculatedAt, now: Date())
            signal(.loop)
        }
    }

    // MARK: - Trio's stores

    struct DeterminationValues {
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

    /// The newest determination from the last 30 minutes, enacted or suggested.
    func latestDetermination() async throws -> DeterminationValues? {
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

    /// Stored readings since `start`, oldest first, in mg/dL. Hand-entered ones are
    /// marked `wasUserEntered`.
    func fetchGlucoseSamples(since start: Date) async throws -> [StoredGlucoseSample] {
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
            (results as? [GlucoseStored] ?? []).compactMap(Self.glucoseSample(from:))
        }
    }

    /// One stored reading as LoopKit's sample: mg/dL as Trio stores it, its
    /// arrow, and whether it was entered by hand; `nil` without a date. Call it
    /// on the reading's context.
    static func glucoseSample(from stored: GlucoseStored) -> StoredGlucoseSample? {
        guard let date = stored.date else { return nil }
        return StoredGlucoseSample(
            syncIdentifier: stored.id?.uuidString,
            startDate: date,
            quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: Double(stored.glucose)),
            trend: stored.direction.flatMap { BloodGlucose.Direction(from: $0) }?.glucoseTrend,
            wasUserEntered: stored.isManual
        )
    }

    /// Trio's override presets, in Trio's order.
    private func fetchOverridePresets() async throws -> [TemporaryPreset] {
        let ids = try await overrideStorage.fetchForOverridePresets()
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "smartwatchOverridePresets"
        let rows: [OverrideStored] = try await CoreDataStack.shared.getNSManagedObject(with: ids, context: context)
        return await context.perform { rows.compactMap(Self.preset(for:)) }
    }

    /// The enabled override, if any: a preset or a custom one.
    private func fetchActiveOverride() async throws -> TemporaryScheduleOverride? {
        guard let id = try await overrideStorage.fetchLatestActiveOverride() else { return nil }
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "smartwatchActiveOverride"
        let rows: [OverrideStored] = try await CoreDataStack.shared.getNSManagedObject(with: [id], context: context)
        return await context.perform {
            guard let row = rows.first, let startDate = row.date else { return nil }
            return TemporaryScheduleOverride(
                context: row.isPreset ? Self.preset(for: row).map { .preset($0) } ?? .custom : .custom,
                settings: Self.settings(for: row),
                startDate: startDate,
                duration: Self.duration(for: row),
                enactTrigger: .local,
                syncIdentifier: row.id.flatMap(UUID.init(uuidString:)) ?? UUID()
            )
        }
    }

    /// Trio's temp target presets, in Trio's order.
    private func fetchTempTargetPresets() async throws -> [TemporaryPreset] {
        let ids = try await tempTargetStorage.fetchForTempTargetPresets()
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "smartwatchTempTargetPresets"
        let rows: [TempTargetStored] = try await CoreDataStack.shared.getNSManagedObject(with: ids, context: context)
        return await context.perform { rows.compactMap(Self.preset(for:)) }
    }

    /// The enabled temp target, if any: a preset or a custom one.
    private func fetchActiveTempTarget() async throws -> TemporaryScheduleOverride? {
        guard let id = try await tempTargetStorage.loadLatestTempTargetConfigurations(fetchLimit: 1).first else {
            return nil
        }
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "smartwatchActiveTempTarget"
        let rows: [TempTargetStored] = try await CoreDataStack.shared.getNSManagedObject(with: [id], context: context)
        return await context.perform {
            guard let row = rows.first, let startDate = row.date else { return nil }
            return TemporaryScheduleOverride(
                context: row.isPreset ? Self.preset(for: row).map { .preset($0) } ?? .custom : .custom,
                settings: Self.settings(for: row),
                startDate: startDate,
                duration: Self.duration(minutes: row.duration, indefinite: false),
                enactTrigger: .local,
                syncIdentifier: row.id ?? UUID()
            )
        }
    }

    // MARK: Presets in LoopKit's types

    /// An override as a `TemporaryPreset`: its target (none when 0) and its
    /// percentage as the insulin needs. Trio may apply the percentage to basal
    /// only, or also to ISF and CR, as the override says; the watch shows the
    /// name only.
    static func preset(for row: OverrideStored) -> TemporaryPreset? {
        guard let id = row.id, let name = row.name else { return nil }
        return TemporaryPreset(
            id: id,
            symbol: nil,
            name: name,
            settings: settings(for: row),
            duration: duration(for: row)
        )
    }

    /// A temp target as a `TemporaryPreset` that sets only a target range.
    static func preset(for row: TempTargetStored) -> TemporaryPreset? {
        guard let id = row.id, let name = row.name else { return nil }
        return TemporaryPreset(
            id: id.uuidString,
            symbol: nil,
            name: name,
            settings: settings(for: row),
            duration: duration(minutes: row.duration, indefinite: false)
        )
    }

    private static func settings(for row: OverrideStored) -> TemporaryPresetSettings {
        TemporaryPresetSettings(
            targetRange: targetRange(milligramsPerDeciliter: row.target),
            insulinNeedsScaleFactor: row.percentage == 100 ? nil : row.percentage / 100
        )
    }

    private static func settings(for row: TempTargetStored) -> TemporaryPresetSettings {
        TemporaryPresetSettings(targetRange: targetRange(milligramsPerDeciliter: row.target))
    }

    /// A single-value range; `nil` for none or 0, which Trio stores for "no target".
    private static func targetRange(milligramsPerDeciliter target: NSDecimalNumber?) -> ClosedRange<LoopQuantity>? {
        guard let target, target.doubleValue > 0 else { return nil }
        let quantity = LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: target.doubleValue)
        return quantity ... quantity
    }

    private static func duration(for row: OverrideStored) -> TemporaryScheduleOverride.Duration {
        duration(minutes: row.duration, indefinite: row.indefinite)
    }

    /// Trio stores durations in minutes; none or 0 is shown as indefinite.
    static func duration(minutes: NSDecimalNumber?, indefinite: Bool) -> TemporaryScheduleOverride.Duration {
        let minutes = minutes.map { Double(truncating: $0) } ?? 0
        return indefinite || minutes <= 0 ? .indefinite : .finite(minutes * 60)
    }

    // MARK: - Device log

    func log(_ manager: SmartwatchManager, _ type: DeviceLogEntryType, _ message: String, device: String? = nil) {
        deviceLogStore.log(managerIdentifier: manager.pluginIdentifier, deviceIdentifier: device, type: type, message: message)
    }

    /// A watch plugin's alert as Trio issues it: from the plugin, whatever manager
    /// it names, so it can't retract or impersonate another device's alert, and at
    /// most time-sensitive. A watch plugin's alerts are about the watch (a missing
    /// companion app); they never break through Focus or the silent switch.
    static func watchPluginAlert(_ alert: Alert, from pluginIdentifier: String) -> Alert {
        Alert(
            identifier: watchPluginAlertIdentifier(alert.identifier, from: pluginIdentifier),
            foregroundContent: alert.foregroundContent,
            backgroundContent: alert.backgroundContent,
            trigger: alert.trigger,
            interruptionLevel: alert.interruptionLevel == .critical ? .timeSensitive : alert.interruptionLevel,
            sound: alert.sound,
            metadata: alert.metadata,
            categoryIdentifier: alert.categoryIdentifier
        )
    }

    static func watchPluginAlertIdentifier(_ identifier: Alert.Identifier, from pluginIdentifier: String) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: pluginIdentifier, alertIdentifier: identifier.alertIdentifier)
    }
}

// MARK: - Observers

extension BaseSmartwatchHost: SettingsObserver {
    /// Units, Max Carbs or the dosing mode (closed loop) may have changed.
    func settingsDidChange(_: TrioSettings) {
        Task { @MainActor in self.signal([.settings, .loop]) }
    }
}

extension BaseSmartwatchHost: PumpSettingsObserver {
    /// Max Bolus may have changed.
    func pumpSettingsDidChange(_: PumpSettings) {
        Task { @MainActor in self.signal(.settings) }
    }
}

extension BaseSmartwatchHost: SnoozeObserver {
    @MainActor func snoozeDidChange(_: Date) {
        signal(.alertMute)
    }
}

// MARK: - SmartwatchManagerDelegate: state and reads

extension BaseSmartwatchHost: SmartwatchManagerDelegate {
    nonisolated func smartwatchManagerDidUpdateState(_ manager: SmartwatchManager) {
        // A removed manager must not bring its saved state back.
        guard isCurrentWatch(manager) else { return }
        rawSmartwatchManager = Self.rawValue(of: manager)
    }

    func smartwatchManagerWantsDeletion(_ manager: SmartwatchManager) async {
        await MainActor.run {
            debug(.watch, "Watch manager \(manager.pluginIdentifier) wants deletion")
            guard isCurrentWatch(manager) else { return }
            smartwatchManager = nil
        }
    }

    func smartwatchManagerGlucoseDisplayUnit(_: SmartwatchManager) async -> LoopUnit {
        displayUnit
    }

    func smartwatchManager(_: SmartwatchManager, glucoseSamplesSince date: Date) async throws -> [StoredGlucoseSample] {
        try await fetchGlucoseSamples(since: date)
    }

    /// From the newest determination of the last 30 minutes: COB, eventual BG and
    /// the sensitivity ratio. IOB is Trio's current IOB, as on the Home screen.
    /// Trio's forecast lines aren't sent: the watch shows none, as before.
    func smartwatchManagerLoopState(_ manager: SmartwatchManager) async -> SmartwatchLoopState {
        let determination: DeterminationValues?
        do {
            determination = try await latestDetermination()
        } catch {
            log(manager, .error, "Unable to read the latest determination for the watch: \(error)")
            determination = nil
        }
        let lastLoop = apsManager.lastLoopDate
        return SmartwatchLoopState(
            lastLoopCompleted: lastLoop == .distantPast ? nil : lastLoop,
            isClosedLoop: Self.isClosedLoop(
                dosingMode: settingsManager.settings.dosingMode,
                isManualTempBasal: apsManager.isManualTempBasal
            ),
            insulinOnBoard: iobService.currentIOB.map {
                InsulinValue(startDate: Date(), value: Double(truncating: $0 as NSNumber))
            },
            carbsOnBoard: determination.flatMap { determination in
                determination.cob.map { CarbValue(startDate: determination.calculatedAt ?? Date(), value: $0) }
            },
            predictedGlucose: [],
            eventualGlucose: determination?.eventualGlucose.map {
                LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: $0)
            },
            sensitivityRatio: determination?.sensitivityRatio
        )
    }

    /// As Trio's own loop ring (LoopView) shows it: closed only while no manual
    /// temp basal runs, because Trio enacts nothing during one.
    static func isClosedLoop(dosingMode: DosingMode, isManualTempBasal: Bool) -> Bool {
        dosingMode == .closed && !isManualTempBasal
    }

    /// The scheduled basal rate the latest determination used.
    func smartwatchManagerScheduledBasalRate(_: SmartwatchManager) async -> LoopQuantity? {
        guard let rate = (try? await latestDetermination())?.scheduledBasal else { return nil }
        return LoopQuantity(unit: .internationalUnitsPerHour, doubleValue: rate)
    }

    func smartwatchManagerTempBasal(_: SmartwatchManager) async -> DoseEntry? {
        guard case let .tempBasal(dose) = deviceDataManager.pumpManager?.status.basalDeliveryState else { return nil }
        return dose
    }

    /// The ISF the latest determination used, including any override (and
    /// autosens or Dynamic ISF).
    func smartwatchManagerInsulinSensitivity(_: SmartwatchManager) async -> LoopQuantity? {
        guard let isf = (try? await latestDetermination())?.insulinSensitivity else { return nil }
        return LoopQuantity(unit: .milligramsPerDeciliterPerInternationalUnit, doubleValue: isf)
    }

    /// The target the latest determination used, including any override or temp target.
    func smartwatchManagerCorrectionRange(_: SmartwatchManager) async -> ClosedRange<LoopQuantity>? {
        guard let target = (try? await latestDetermination())?.target else { return nil }
        let quantity = LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: target)
        return quantity ... quantity
    }

    func smartwatchManagerOverridePresets(_ manager: SmartwatchManager) async -> [TemporaryPreset] {
        do {
            return try await fetchOverridePresets()
        } catch {
            log(manager, .error, "Unable to read the override presets for the watch: \(error)")
            return []
        }
    }

    func smartwatchManagerActiveOverride(_ manager: SmartwatchManager) async -> TemporaryScheduleOverride? {
        do {
            return try await fetchActiveOverride()
        } catch {
            log(manager, .error, "Unable to read the active override for the watch: \(error)")
            return nil
        }
    }

    /// Empty, not nil, when the user has none: Trio has temp targets.
    func smartwatchManagerTempTargetPresets(_ manager: SmartwatchManager) async -> [TemporaryPreset]? {
        do {
            return try await fetchTempTargetPresets()
        } catch {
            log(manager, .error, "Unable to read the temp target presets for the watch: \(error)")
            return []
        }
    }

    func smartwatchManagerActiveTempTarget(_ manager: SmartwatchManager) async -> TemporaryScheduleOverride? {
        do {
            return try await fetchActiveTempTarget()
        } catch {
            log(manager, .error, "Unable to read the active temp target for the watch: \(error)")
            return nil
        }
    }

    /// When Trio's snooze ends, as every snooze surface stores it.
    func smartwatchManagerAlertMuteEnd(_: SmartwatchManager) async -> Date? {
        guard let end = UserDefaults.standard.object(forKey: "UserNotificationsManager.snoozeUntilDate") as? Date,
              end > Date()
        else { return nil }
        return end
    }

    func smartwatchManagerMaximumBolus(_: SmartwatchManager) async -> Double? {
        Double(truncating: settingsManager.pumpSettings.maxBolus as NSNumber)
    }

    func smartwatchManagerMaximumCarbEntry(_: SmartwatchManager) async -> Double? {
        Double(truncating: settingsManager.settings.maxCarbs as NSNumber)
    }

    func smartwatchManagerSupportedBolusVolumes(_: SmartwatchManager) async -> [Double] {
        deviceDataManager.pumpManager?.supportedBolusVolumes ?? []
    }

    // Trio's carb model has no per-entry absorption time, so
    // `smartwatchManagerDefaultCarbAbsorptionTimes` keeps its default, nil: the
    // watch doesn't ask for one.
}

// MARK: - DeviceManagerDelegate: the plugin's log and alerts

extension BaseSmartwatchHost {
    nonisolated func deviceManager(
        _ manager: DeviceManager,
        logEventForDeviceIdentifier deviceIdentifier: String?,
        type: DeviceLogEntryType,
        message: String,
        completion: ((Error?) -> Void)?
    ) {
        deviceLogStore.log(
            managerIdentifier: manager.pluginIdentifier,
            deviceIdentifier: deviceIdentifier,
            type: type,
            message: message,
            completion: completion
        )
    }

    /// Issues the plugin's alert about the watch as Trio's own alert from this
    /// plugin, capped by `watchPluginAlert`.
    nonisolated func issueAlert(_ alert: Alert) {
        guard let manager = smartwatchManager else { return }
        let watchAlert = Self.watchPluginAlert(alert, from: manager.pluginIdentifier)
        let content = watchAlert.foregroundContent ?? watchAlert.backgroundContent
        var note = "Watch plugin alert: \(content.title): \(content.body)"
        if alert.interruptionLevel != watchAlert.interruptionLevel {
            note += " (critical lowered to time-sensitive)"
        }
        if alert.identifier != watchAlert.identifier {
            note += " (issued as \(watchAlert.identifier.value), not \(alert.identifier.value))"
        }
        log(manager, .error, note)
        trioAlertManager.issueAlert(watchAlert)
    }

    nonisolated func retractAlert(identifier: Alert.Identifier) {
        guard let manager = smartwatchManager else { return }
        trioAlertManager.retractAlert(identifier: Self.watchPluginAlertIdentifier(identifier, from: manager.pluginIdentifier))
    }

    // As for the pump: Trio's alert manager keeps its own history and
    // deduplicates, so these answer that nothing is stored.

    func doesIssuedAlertExist(identifier _: Alert.Identifier) async throws -> Bool { false }

    func lookupAllUnretracted(managerIdentifier _: String) async throws -> [PersistedAlert] { [] }

    func lookupAllUnacknowledgedUnretracted(managerIdentifier _: String) async throws -> [PersistedAlert] { [] }

    func recordRetractedAlert(_: Alert, at _: Date) async throws {}
}

// MARK: - SmartwatchManagerOnboardingDelegate

extension BaseSmartwatchHost: SmartwatchManagerOnboardingDelegate {
    func smartwatchManagerOnboarding(didCreateSmartwatchManager manager: SmartwatchManagerUI) {
        debug(.watch, "Watch manager \(manager.pluginIdentifier) created")
        smartwatchManager = manager
    }

    func smartwatchManagerOnboarding(didOnboardSmartwatchManager manager: SmartwatchManagerUI) {
        debug(.watch, "Watch manager \(manager.pluginIdentifier) onboarded")
        Task { @MainActor in self.refresh() }
    }
}

/// The host's change signals for its watch manager: collected until the next main
/// run loop turn, then handed to it as one `hostDataDidChange` with all of them.
final class SmartwatchChangeBatch {
    private let manager: @MainActor() -> SmartwatchManager?
    @MainActor private var pending: SmartwatchHostDataChange = []

    init(manager: @escaping @MainActor() -> SmartwatchManager?) {
        self.manager = manager
    }

    @MainActor func signal(_ changes: SmartwatchHostDataChange) {
        guard manager() != nil else { return }
        let isScheduled = !pending.isEmpty
        pending.formUnion(changes)
        guard !isScheduled else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.send() }
        }
    }

    /// Drops what is pending: the watch manager is being told everything changed.
    @MainActor func discardPending() {
        pending = []
    }

    @MainActor private func send() {
        let changes = pending
        pending = []
        guard !changes.isEmpty, let manager = manager() else { return }
        manager.hostDataDidChange(changes)
    }
}

/// The plugin's 0 g recommendation reads for its bolus context, made after every
/// change: an answer is logged only when it differs from the last one.
struct ContextRecommendationLog {
    private var last: Double?

    /// Whether `units` should be logged; it becomes the last answer.
    mutating func shouldLog(_ units: Double) -> Bool {
        guard units != last else { return false }
        last = units
        return true
    }
}

extension BloodGlucose.Direction {
    /// The trend arrow as LoopKit's `GlucoseTrend`.
    var glucoseTrend: GlucoseTrend? {
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
