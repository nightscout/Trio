import Combine
import CoreData
import Foundation
import Swinject
import WatchConnectivity

/// Protocol defining the base functionality for Watch communication
// TODO: Complete this
protocol WatchManager {}

/// Main implementation of the Watch communication manager
/// Handles bidirectional communication between iPhone and Apple Watch
final class BaseWatchManager: NSObject, WCSessionDelegate, Injectable, WatchManager {
    private var session: WCSession?

    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var apsManager: APSManager!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var determinationStorage: DeterminationStorage!
    @Injected() private var overrideStorage: OverrideStorage!
    @Injected() private var tempTargetStorage: TempTargetsStorage!

    private var units: GlucoseUnits = .mgdL

    private var coreDataPublisher: AnyPublisher<Set<NSManagedObject>, Never>?
    private var subscriptions = Set<AnyCancellable>()

    typealias PumpEvent = PumpEventStored.EventType

    let backgroundContext = CoreDataStack.shared.newTaskContext()
    let viewContext = CoreDataStack.shared.persistentContainer.viewContext

    init(resolver: Resolver) {
        super.init()
        injectServices(resolver)
        setupWatchSession()
        units = settingsManager.settings.units

        // Observer for OrefDetermination and adjustments
        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: DispatchQueue.global(qos: .background))
                .share()
                .eraseToAnyPublisher()

        // Observer for glucose and manual glucose
        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    let state = await self.setupWatchState()
                    self.sendDataToWatch(state)
                }
            }
            .store(in: &subscriptions)

        registerHandlers()
    }

    private func registerHandlers() {
        coreDataPublisher?.filterByEntityName("OrefDetermination").sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                let state = await self.setupWatchState()
                self.sendDataToWatch(state)
            }
        }.store(in: &subscriptions)

        // Due to the Batch insert this only is used for observing Deletion of Glucose entries
        coreDataPublisher?.filterByEntityName("GlucoseStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                let state = await self.setupWatchState()
                self.sendDataToWatch(state)
            }
        }.store(in: &subscriptions)

        coreDataPublisher?.filterByEntityName("OverrideStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                let state = await self.setupWatchState()
                self.sendDataToWatch(state)
            }
        }.store(in: &subscriptions)

        coreDataPublisher?.filterByEntityName("TempTargetStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                let state = await self.setupWatchState()
                self.sendDataToWatch(state)
            }
        }.store(in: &subscriptions)
    }

    /// Sets up the WatchConnectivity session if the device supports it
    private func setupWatchSession() {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
            self.session = session

            print("📱 Phone session setup - isPaired: \(session.isPaired)")
        } else {
            print("📱 WCSession is not supported on this device")
        }
    }

    /// Attempts to reestablish the Watch connection if it becomes unreachable
    private func retryConnection() {
        guard let session = session else { return }

        if !session.isReachable {
            print("📱 Attempting to reactivate session...")
            session.activate()
        }
    }

    /// Prepares the current state data to be sent to the Watch
    /// - Returns: WatchState containing current glucose readings and trends and determination infos for displaying cob and iob in the view
    private func setupWatchState() async -> WatchState {
        // Get NSManagedObjectIDs
        let glucoseIds = await fetchGlucose()
        // TODO: - if we want that the watch immediately displays updated cob and iob values when entered via treatment view from phone, we would need to use a predicate here that also filters for NON-ENACTED Determinations
        let determinationIds = await determinationStorage.fetchLastDeterminationObjectID(
            predicate: NSPredicate.predicateFor30MinAgoForDetermination
        )
        let overridePresetIds = await overrideStorage.fetchForOverridePresets()
        let tempTargetPresetIds = await tempTargetStorage.fetchForTempTargetPresets()

        // Get NSManagedObjects
        let glucoseObjects: [GlucoseStored] = await CoreDataStack.shared
            .getNSManagedObject(with: glucoseIds, context: backgroundContext)
        let determinationObjects: [OrefDetermination] = await CoreDataStack.shared
            .getNSManagedObject(with: determinationIds, context: backgroundContext)
        let overridePresetObjects: [OverrideStored] = await CoreDataStack.shared
            .getNSManagedObject(with: overridePresetIds, context: backgroundContext)
        let tempTargetPresetObjects: [TempTargetStored] = await CoreDataStack.shared
            .getNSManagedObject(with: tempTargetPresetIds, context: backgroundContext)

        return await backgroundContext.perform {
            var watchState = WatchState()

            // Set lastLoopDate
            let lastLoopMinutes = Int((Date().timeIntervalSince(self.apsManager.lastLoopDate) - 30) / 60) + 1
            if lastLoopMinutes > 1440 {
                watchState.lastLoopTime = "--"
            } else {
                watchState.lastLoopTime = "\(lastLoopMinutes)m"
            }

            // Set IOB and COB from latest determination
            if let latestDetermination = determinationObjects.first {
                let iob = latestDetermination.iob ?? 0
                watchState.iob = Formatter.decimalFormatterWithTwoFractionDigits.string(from: iob)

                let cob = NSNumber(value: latestDetermination.cob)
                watchState.cob = Formatter.integerFormatter.string(from: cob)
            }

            // Set override presets with their enabled status
            watchState.overridePresets = overridePresetObjects.map { override in
                OverridePresetWatch(
                    name: override.name ?? "",
                    isEnabled: override.enabled
                )
            }

            guard let latestGlucose = glucoseObjects.first else {
                return watchState
            }

            // Map glucose values
            watchState.glucoseValues = glucoseObjects.compactMap { glucose in
                guard let date = glucose.date else { return nil }
                return (date: date, glucose: Double(glucose.glucose))
            }
            .sorted { $0.date < $1.date }

            // Set current glucose with proper formatting
            watchState.currentGlucose = "\(latestGlucose.glucose)"

            // Convert direction to trend string
            watchState.trend = latestGlucose.direction

            // Calculate delta if we have at least 2 readings
            if glucoseObjects.count >= 2 {
                let deltaValue = glucoseObjects[0].glucose - glucoseObjects[1].glucose
                let formattedDelta = Formatter.glucoseFormatter(for: self.units)
                    .string(from: NSNumber(value: abs(deltaValue))) ?? "0"
                watchState.delta = deltaValue < 0 ? "-\(formattedDelta)" : "+\(formattedDelta)"
            }

            // Set temp target presets with their enabled status
            watchState.tempTargetPresets = tempTargetPresetObjects.map { tempTarget in
                TempTargetPresetWatch(
                    name: tempTarget.name ?? "",
                    isEnabled: tempTarget.enabled
                )
            }

            // Set units
            watchState.units = self.units

            print(
                "📱 Setup WatchState - currentGlucose: \(watchState.currentGlucose ?? "nil"), trend: \(watchState.trend ?? "nil"), delta: \(watchState.delta ?? "nil"), values: \(watchState.glucoseValues.count)"
            )

            return watchState
        }
    }

    /// Fetches recent glucose readings from CoreData
    /// - Returns: Array of NSManagedObjectIDs for glucose readings
    private func fetchGlucose() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.glucose,
            key: "date",
            ascending: false,
            fetchLimit: 288
        )

        return await backgroundContext.perform {
            guard let fetchedResults = results as? [GlucoseStored] else { return [] }

            return fetchedResults.map(\.objectID)
        }
    }

    // MARK: - Send Data to Watch

    /// Sends the state of type WatchState to the connected Watch
    /// - Parameter state: Current WatchState containing glucose data to be sent
    func sendDataToWatch(_ state: WatchState) {
        guard let session = session, session.isReachable else {
            print("⌚️ Watch not reachable")
            return
        }

        let message: [String: Any] = [
            "currentGlucose": state.currentGlucose ?? "0",
            "trend": state.trend ?? "?",
            "delta": state.delta ?? "0",
            "glucoseValues": state.glucoseValues.map { value in
                [
                    "glucose": value.glucose,
                    "date": value.date.timeIntervalSince1970
                ]
            },
            "iob": state.iob ?? "0",
            "cob": state.cob ?? "0",
            "lastLoopTime": state.lastLoopTime ?? "--",
            "overridePresets": state.overridePresets.map { preset in
                [
                    "name": preset.name,
                    "isEnabled": preset.isEnabled
                ]
            },
            "tempTargetPresets": state.tempTargetPresets.map { preset in
                [
                    "name": preset.name,
                    "isEnabled": preset.isEnabled
                ]
            }
        ]

        print("📱 Sending to watch - Message content:")
        message.forEach { key, value in
            print("📱 \(key): \(value) (type: \(type(of: value)))")
        }

        session.sendMessage(message, replyHandler: nil) { error in
            print("❌ Error sending data: \(error.localizedDescription)")
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("📱 Phone session activation failed: \(error.localizedDescription)")
            return
        }

        print("📱 Phone session activated with state: \(activationState.rawValue)")
        print("📱 Phone isReachable after activation: \(session.isReachable)")

        // Try to send initial data after activation
        Task {
            let state = await self.setupWatchState()
            self.sendDataToWatch(state)
        }
    }

    func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            if let bolusAmount = message["bolus"] as? Double
            {
                self?.handleBolusRequest(Decimal(bolusAmount))
            }

            if let carbsAmount = message["carbs"] as? Int,
               let timestamp = message["date"] as? TimeInterval
            {
                let date = Date(timeIntervalSince1970: timestamp)
                print("📱 Received carbs request from watch: \(carbsAmount)g at \(date)")
                self?.handleCarbsRequest(carbsAmount, date)
            }

            if message["cancelOverride"] as? Bool == true {
                print("📱 Received cancel override request from watch")
                self?.handleCancelOverride()
            }

            if let presetName = message["activateOverride"] as? String {
                print("📱 Received activate override request from watch for preset: \(presetName)")
                self?.handleActivateOverride(presetName)
            }

            if let presetName = message["activateTempTarget"] as? String {
                print("📱 Received activate temp target request from watch for preset: \(presetName)")
                self?.handleActivateTempTarget(presetName)
            }

            if message["cancelTempTarget"] as? Bool == true {
                print("📱 Received cancel temp target request from watch")
                self?.handleCancelTempTarget()
            }
        }
    }

    #if os(iOS)
        func sessionDidBecomeInactive(_: WCSession) {}
        func sessionDidDeactivate(_ session: WCSession) {
            session.activate()
        }
    #endif

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("📱 Phone reachability changed: \(session.isReachable)")

        if session.isReachable {
            // Try to send data when connection is established
            Task {
                let state = await self.setupWatchState()
                self.sendDataToWatch(state)
            }
        } else {
            // Try to reconnect after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.retryConnection()
            }
        }
    }

    /// Processes bolus requests received from the Watch
    /// - Parameter amount: The requested bolus amount in units
    private func handleBolusRequest(_ amount: Decimal) {
        Task {
            await apsManager.enactBolus(amount: Double(amount), isSMB: false)
            print("📱 Enacted bolus via APS Manager: \(amount)U")
        }
    }

    /// Handles carbs entry requests received from the Watch
    /// - Parameters:
    ///   - amount: The carbs amount in grams
    ///   - date: Timestamp for the carbs entry
    private func handleCarbsRequest(_ amount: Int, _ date: Date) {
        Task {
            let context = CoreDataStack.shared.newTaskContext()

            await context.perform {
                let carbs = CarbEntryStored(context: context)
                carbs.carbs = Double(truncating: amount as NSNumber)
                carbs.date = date
                carbs.id = UUID()

                // TODO: add FPU

                do {
                    guard context.hasChanges else { return }
                    try context.save()
                    print("📱 Saved carbs from watch: \(amount)g at \(date)")
                } catch {
                    print("❌ Error saving carbs: \(error.localizedDescription)")
                }
            }
        }
    }

    private func handleCancelOverride() {
        Task {
            let context = CoreDataStack.shared.newTaskContext()

            if let overrideId = await overrideStorage.fetchLatestActiveOverride() {
                let override = await context.perform {
                    context.object(with: overrideId) as? OverrideStored
                }

                await context.perform {
                    if let activeOverride = override {
                        activeOverride.enabled = false

                        do {
                            guard context.hasChanges else { return }
                            try context.save()
                            print("📱 Successfully cancelled override")

                            // Send notification to update Adjustments UI
                            Foundation.NotificationCenter.default.post(
                                name: .didUpdateOverrideConfiguration,
                                object: nil
                            )
                        } catch {
                            print("❌ Error cancelling override: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    private func handleActivateOverride(_ presetName: String) {
        Task {
            let context = CoreDataStack.shared.newTaskContext()

            // Fetch all presets to find the one to activate
            let presetIds = await overrideStorage.fetchForOverridePresets()
            let presets: [OverrideStored] = await CoreDataStack.shared
                .getNSManagedObject(with: presetIds, context: context)

            // Check for active override
            if let activeOverrideId = await overrideStorage.fetchLatestActiveOverride() {
                let activeOverride = await context.perform {
                    context.object(with: activeOverrideId) as? OverrideStored
                }

                // Deactivate if exists
                if let override = activeOverride {
                    await context.perform {
                        override.enabled = false
                    }
                }
            }

            // Activate the selected preset
            await context.perform {
                if let presetToActivate = presets.first(where: { $0.name == presetName }) {
                    presetToActivate.enabled = true
                    presetToActivate.date = Date()

                    do {
                        guard context.hasChanges else { return }
                        try context.save()
                        print("📱 Successfully activated override: \(presetName)")

                        // Send notification to update Adjustments UI
                        Foundation.NotificationCenter.default.post(
                            name: .didUpdateOverrideConfiguration,
                            object: nil
                        )
                    } catch {
                        print("❌ Error activating override: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func handleCancelTempTarget() {
        Task {
            let context = CoreDataStack.shared.newTaskContext()

            if let tempTargetId = await tempTargetStorage.loadLatestTempTargetConfigurations(fetchLimit: 1).first {
                let tempTarget = await context.perform {
                    context.object(with: tempTargetId) as? TempTargetStored
                }

                await context.perform {
                    if let activeTempTarget = tempTarget {
                        activeTempTarget.enabled = false

                        do {
                            guard context.hasChanges else { return }
                            try context.save()
                            print("📱 Successfully cancelled temp target")

                            // To cancel the temp target also for oref
                            self.tempTargetStorage.saveTempTargetsToStorage([TempTarget.cancel(at: Date())])

                            // Send notification to update Adjustments UI
                            Foundation.NotificationCenter.default.post(
                                name: .didUpdateTempTargetConfiguration,
                                object: nil
                            )
                        } catch {
                            print("❌ Error cancelling temp target: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    private func handleActivateTempTarget(_ presetName: String) {
        Task {
            let context = CoreDataStack.shared.newTaskContext()

            // Fetch all presets to find the one to activate
            let presetIds = await tempTargetStorage.fetchForTempTargetPresets()
            let presets: [TempTargetStored] = await CoreDataStack.shared
                .getNSManagedObject(with: presetIds, context: context)

            // Check for active temp target
            if let activeTempTargetId = await tempTargetStorage.loadLatestTempTargetConfigurations(fetchLimit: 1).first {
                let activeTempTarget = await context.perform {
                    context.object(with: activeTempTargetId) as? TempTargetStored
                }

                // Deactivate if exists
                if let tempTarget = activeTempTarget {
                    await context.perform {
                        tempTarget.enabled = false
                    }
                }
            }

            // Activate the selected preset
            await context.perform {
                if let presetToActivate = presets.first(where: { $0.name == presetName }) {
                    presetToActivate.enabled = true
                    presetToActivate.date = Date()

                    do {
                        guard context.hasChanges else { return }
                        try context.save()
                        print("📱 Successfully activated temp target: \(presetName)")

                        // To activate the temp target also in oref
                        let tempTarget = TempTarget(
                            name: presetToActivate.name,
                            createdAt: Date(),
                            targetTop: presetToActivate.target?.decimalValue,
                            targetBottom: presetToActivate.target?.decimalValue,
                            duration: presetToActivate.duration?.decimalValue ?? 0,
                            enteredBy: TempTarget.local,
                            reason: TempTarget.custom,
                            isPreset: true,
                            enabled: true,
                            halfBasalTarget: presetToActivate.halfBasalTarget?.decimalValue
                        )
                        self.tempTargetStorage.saveTempTargetsToStorage([tempTarget])

                        // Send notification to update Adjustments UI
                        Foundation.NotificationCenter.default.post(
                            name: .didUpdateTempTargetConfiguration,
                            object: nil
                        )
                    } catch {
                        print("❌ Error activating temp target: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
