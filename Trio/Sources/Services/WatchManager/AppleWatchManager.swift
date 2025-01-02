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

    private var units: GlucoseUnits = .mgdL

    private var coreDataPublisher: AnyPublisher<Set<NSManagedObject>, Never>?
    private var subscriptions = Set<AnyCancellable>()

    typealias PumpEvent = PumpEventStored.EventType

    let glucoseFetchContext = CoreDataStack.shared.newTaskContext()
    let viewContext = CoreDataStack.shared.persistentContainer.viewContext

    init(resolver: Resolver) {
        super.init()
        injectServices(resolver)
        setupWatchSession()
        units = settingsManager.settings.units

        // Observer for OrefDetermination
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
                    self.sendGlucoseData(state)
                }
            }
            .store(in: &subscriptions)
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
    /// - Returns: WatchState containing current glucose readings and trends
    private func setupWatchState() async -> WatchState {
        let ids = await fetchGlucose()

        // Get NSManagedObjects
        let glucoseObjects: [GlucoseStored] = await CoreDataStack.shared
            .getNSManagedObject(with: ids, context: glucoseFetchContext)

        return await glucoseFetchContext.perform {
            var watchState = WatchState()

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
            onContext: glucoseFetchContext,
            predicate: NSPredicate.glucose,
            key: "date",
            ascending: false,
            fetchLimit: 288
        )

        return await glucoseFetchContext.perform {
            guard let fetchedResults = results as? [GlucoseStored] else { return [] }

            return fetchedResults.map(\.objectID)
        }
    }

    // MARK: - Send Data to Watch

    /// Sends the current glucose state to the connected Watch
    /// - Parameter state: Current WatchState containing glucose data to be sent
    func sendGlucoseData(_ state: WatchState) {
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
            }
        ]

        print("📱 Sending to watch: currentGlucose: \(state.currentGlucose ?? "nil"), trend: \(state.trend ?? "nil")")

        session.sendMessage(message, replyHandler: nil) { error in
            print("❌ Error sending glucose data: \(error.localizedDescription)")
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
            self.sendGlucoseData(state)
        }
    }

    func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            if let bolusAmount = message["bolus"] as? Double,
               let isExternal = message["isExternal"] as? Bool
            {
                print("📱 Received \(isExternal ? "external insulin" : "bolus") request from watch: \(bolusAmount)U")
                if isExternal {
                    self?.handleExternalInsulin(Decimal(bolusAmount))
                } else {
                    self?.handleBolusRequest(Decimal(bolusAmount))
                }
            }

            if let carbsAmount = message["carbs"] as? Int,
               let timestamp = message["date"] as? TimeInterval
            {
                let date = Date(timeIntervalSince1970: timestamp)
                print("📱 Received carbs request from watch: \(carbsAmount)g at \(date)")
                self?.handleCarbsRequest(carbsAmount, date)
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
                self.sendGlucoseData(state)
            }
        } else {
            // Try to reconnect after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.retryConnection()
            }
        }
    }

    /// Handles external insulin entries received from the Watch
    /// - Parameter amount: The insulin amount in units to be recorded
    private func handleExternalInsulin(_ amount: Decimal) {
        Task {
            let context = CoreDataStack.shared.newTaskContext()

            await context.perform {
                // Create Bolus
                let bolus = BolusStored(context: context)
                bolus.amount = amount as NSDecimalNumber
                bolus.isSMB = false
                bolus.isExternal = true

                // Create PumpEvent
                let pumpEvent = PumpEventStored(context: context)
                pumpEvent.id = UUID().uuidString
                pumpEvent.timestamp = Date()
                pumpEvent.type = PumpEvent.bolus.rawValue
                pumpEvent.bolus = bolus
                pumpEvent.isUploadedToNS = false
                pumpEvent.isUploadedToHealth = false
                pumpEvent.isUploadedToTidepool = false

                do {
                    guard context.hasChanges else { return }
                    try context.save()
                    print("📱 Saved external insulin and pump event from watch: \(amount)U")
                } catch {
                    print("❌ Error saving external insulin and pump event: \(error.localizedDescription)")
                }
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
}
