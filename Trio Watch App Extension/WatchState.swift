import Foundation
import SwiftUI
import WatchConnectivity

/// WatchState manages the communication between the Watch app and the iPhone app using WatchConnectivity.
/// It handles glucose data synchronization and sending treatment requests (bolus, carbs) to the phone.
@Observable final class WatchState: NSObject, WCSessionDelegate {
    /// Shared, not created in a view: every throwaway instance from a view re-init would take over the
    /// (weak) session delegate and then be released, leaving nothing to receive from the phone.
    static let shared = WatchState()

    // MARK: - Properties

    /// The WatchConnectivity session instance used for communication
    var session: WCSession?
    /// Indicates if the paired iPhone is currently reachable
    var isReachable = false

    var lastWatchStateUpdate: TimeInterval?

    /// main view relevant metrics
    var currentGlucose: String = "--"
    var currentGlucoseColorString: String = "#ffffff"
    var trend: String? = ""
    var delta: String? = "--"
    var glucoseValues: [(date: Date, glucose: Double, color: Color)] = []
    var minYAxisValue: Decimal = 39
    var maxYAxisValue: Decimal = 200
    var cob: String? = "--"
    var iob: String? = "--"
    var lastLoopTime: String? = "--"
    var overridePresets: [OverridePresetWatch] = []
    var tempTargetPresets: [TempTargetPresetWatch] = []

    /// treatments inputs
    /// used to store carbs for combined meal-bolus-treatments
    var carbsAmount: Int = 0
    var fatAmount: Int = 0
    var proteinAmount: Int = 0
    var bolusAmount: Double = 0.0
    var confirmationProgress: Double = 0.0

    // Safety limits
    var maxBolus: Decimal = 10
    var maxCarbs: Decimal = 250
    var maxFat: Decimal = 250
    var maxProtein: Decimal = 250

    // Pump specific dosing increment
    var bolusIncrement: Decimal = 0.05
    var confirmBolusFaster: Bool = false

    // Forecast options
    var showForecast: Bool = false
    var isForecastCone: Bool = false
    var forecastStartDate: Date?
    var forecastConeMin: [Double] = []
    var forecastConeMax: [Double] = []
    var forecastLines: [String: [Double]] = [:] // "iob" / "cob" / "uam" / "zt" -> values

    // Acknowlegement handling
    var showCommsAnimation: Bool = false
    var showAcknowledgmentBanner: Bool = false
    var acknowledgementStatus: AcknowledgementStatus = .pending
    var acknowledgmentMessage: String = ""
    var shouldNavigateToRoot: Bool = true

    // Bolus calculation progress
    var showBolusCalculationProgress: Bool = false

    // Meal bolus-specific properties
    var mealBolusStep: MealBolusStep = .savingCarbs
    var isMealBolusCombo: Bool = false

    var recommendedBolus: Decimal = 0

    /// Snapshots older than this are dropped at the top of the WC delegate
    /// methods. Single source of truth for both `didReceiveMessage` and
    /// `didReceiveUserInfo`.
    private static let maxAcceptableMessageAgeInMinutes: TimeInterval = 15 * 60

    /// In memory only: the UI starts empty on every launch, so a payload must never be dropped as a
    /// duplicate of one a previous launch displayed.
    private var lastAcceptedStateDate: Date?

    private static let syncingAnimationTimeout: TimeInterval = 10

    // MARK: - Glucose history sync

    enum GlucoseResync: Int, Comparable {
        case backfill
        case full

        static func < (lhs: GlucoseResync, rhs: GlucoseResync) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Only accessed on the main queue, like everything below.
    private var glucoseHistory = WatchGlucoseHistory()
    private var hasPendingGlucoseHistoryUpdate = false
    private var pendingGlucoseResync: GlucoseResync?
    private var isGlucoseResyncInFlight = false
    private var glucoseResyncAttempts = 0
    private static let maxGlucoseResyncAttempts = 3
    /// Set once a full history fails its own checksum. A delta that doesn't verify is no such sign:
    /// readings deleted or backfilled on the phone cause that too.
    private var isGlucoseDeltaSyncDisabled = false

    // MARK: - Debouncing and batch processing helpers

    /// Temporary storage for new data arriving via WatchConnectivity.
    private var pendingData: [String: Any] = [:]

    /// Work item to schedule finalizing the pending data.
    private var finalizeWorkItem: DispatchWorkItem?

    /// A flag to tell the UI we’re still updating.
    var showSyncingAnimation: Bool = false

    var deviceType = WatchSize.current

    override init() {
        super.init()
        restoreGlucoseHistory()
        setupSession()
    }

    /// Configures the WatchConnectivity session if supported on the device
    private func setupSession() {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            self.session = session
            if session.activationState == .activated {
                // Activated before this delegate was installed: the activation callback won't come.
                DispatchQueue.main.async {
                    self.handleSessionActivated(session)
                }
            } else {
                session.activate()
            }
            Task {
                await WatchLogger.shared.log("⌚️ WCSession setup complete.")
            }
        } else {
            Task {
                await WatchLogger.shared.log("⌚️ WCSession is not supported on this device")
            }
        }
    }

    // MARK: – Handle Acknowledgement Messages FROM Phone

    func handleAcknowledgment(success: Bool, message: String, isFinal: Bool = true) {
        Task {
            await WatchLogger.shared.log("Handling acknowledgment: \(message), success: \(success), isFinal: \(isFinal)")
        }

        if success {
            Task {
                await WatchLogger.shared.log("⌚️ Acknowledgment received: \(message)")
            }
            acknowledgementStatus = .success
            acknowledgmentMessage = message

            // Hide progress animation
            DispatchQueue.main.async {
                self.showCommsAnimation = false
            }
        } else {
            Task {
                await WatchLogger.shared.log("⌚️ Acknowledgment failed: \(message)")
            }

            // Hide progress animation
            DispatchQueue.main.async {
                self.showCommsAnimation = false
            }
            acknowledgementStatus = .failure
            acknowledgmentMessage = "\(message)"
        }

        if isFinal {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.showAcknowledgmentBanner = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.showAcknowledgmentBanner = false
                self.showSyncingAnimation = false // Just ensure this is 100% set to false
                Task {
                    await WatchLogger.shared.log("Cleared ack banner and syncing animation")
                }
            }
        }
    }

    // MARK: - WCSessionDelegate

    /// Called when the session has completed activation
    /// Updates the reachability status and logs the activation state
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                Task {
                    await WatchLogger.shared.log("⌚️ Watch session activation failed: \(error)", force: true)
                    await WatchLogger.shared.log("⌚️ Saving logs to disk as fallback!")
                    await WatchLogger.shared.persistLogsLocally()
                }
                return
            }

            if activationState == .activated {
                Task {
                    await WatchLogger.shared.log("⌚️ Watch session activated with state: \(activationState.rawValue)")
                }

                self.handleSessionActivated(session)
            }
        }
    }

    private func handleSessionActivated(_ session: WCSession) {
        isReachable = session.isReachable

        Task {
            await WatchLogger.shared.log("⌚️ Watch isReachable after activation: \(session.isReachable)")
        }

        let context = session.receivedApplicationContext
        if !context.isEmpty {
            acceptWatchStatePayload(context)
        }

        forceConditionalWatchStateUpdate()
    }

    func refreshIfNeeded() {
        DispatchQueue.main.async {
            guard let session = self.session, session.activationState == .activated else { return }
            self.forceConditionalWatchStateUpdate()
        }
    }

    /// Handles incoming messages from the paired iPhone when Phone is in the foreground
    func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        Task {
            await WatchLogger.shared.log("⌚️ Watch received data: \(message)")
        }

        // Ack at top level — no `watchState` wrapper, no staleness check.
        if let acknowledged = message[WatchMessageKeys.acknowledged] as? Bool,
           let ackMessage = message[WatchMessageKeys.message] as? String,
           let ackCodeRaw = message[WatchMessageKeys.ackCode] as? String
        {
            Task {
                await WatchLogger.shared
                    .log("⌚️ Handling ack with message: \(ackMessage), success: \(acknowledged), ackCode: \(ackCodeRaw)")
            }
            DispatchQueue.main.async {
                self.showSyncingAnimation = false
            }
            processWatchMessage(message)
            return
        }

        // Recommended bolus is also not part of the WatchState message.
        if let recommendedBolus = message[WatchMessageKeys.recommendedBolus] as? NSNumber {
            Task {
                await WatchLogger.shared.log("⌚️ Received recommended bolus: \(recommendedBolus)")
            }
            DispatchQueue.main.async {
                self.recommendedBolus = recommendedBolus.decimalValue
                self.showBolusCalculationProgress = false
            }
            return
        }

        handleIncomingWatchStatePayload(message)
    }

    func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleIncomingWatchStatePayload(userInfo)
    }

    func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleIncomingWatchStatePayload(applicationContext)
    }

    private func handleIncomingWatchStatePayload(_ dictionary: [String: Any]) {
        DispatchQueue.main.async {
            self.acceptWatchStatePayload(dictionary)
        }
    }

    /// Doesn't end the syncing animation when a payload is rejected: a stale or duplicate payload can
    /// arrive while a request is still in flight.
    @discardableResult func acceptWatchStatePayload(_ dictionary: [String: Any]) -> Bool {
        guard let payload = dictionary[WatchMessageKeys.watchState] as? [String: Any],
              let timestamp = payload[WatchMessageKeys.date] as? TimeInterval
        else {
            Task { await WatchLogger.shared.log("⌚️ Faulty watch state payload — skipping", force: true) }
            return false
        }
        let date = Date(timeIntervalSince1970: timestamp)

        // Wall-clock staleness gate. Drops the queued backlog cheaply when
        // the watch app wakes after long disuse; without it, every payload
        // schedules merge + UI work.
        guard date >= Date().addingTimeInterval(-Self.maxAcceptableMessageAgeInMinutes) else {
            Task { await WatchLogger.shared.log("⌚️ Skipping stale watch state (\(date))") }
            adoptGlucoseHistory(fromStale: payload)
            return false
        }

        // The same state can arrive both as a message and as the application context.
        if let lastAccepted = lastAcceptedStateDate, date <= lastAccepted {
            Task { await WatchLogger.shared.log("⌚️ Skipping duplicate watch state (\(date))") }
            if date == lastAccepted {
                // A request's full reply shares its stamp with the context, which only carries recent readings.
                applyGlucoseHistory(from: payload)
                if hasPendingGlucoseHistoryUpdate {
                    publishGlucoseHistory()
                }
            }
            return false
        }

        lastAcceptedStateDate = date
        applyGlucoseHistory(from: payload)

        var uiPayload = payload
        uiPayload.removeValue(forKey: WatchMessageKeys.glucoseValues)
        scheduleUIUpdate(with: uiPayload)
        return true
    }

    /// A stale payload's IOB, COB and trend are outdated, but its glucose readings are not.
    private func adoptGlucoseHistory(fromStale payload: [String: Any]) {
        guard let newest = WatchGlucoseSync.newestTimestamp(in: payload),
              newest > glucoseHistory.newestTimestamp ?? -.infinity
        else { return }

        Task { await WatchLogger.shared.log("⌚️ Taking over glucose readings from stale watch state") }
        applyGlucoseHistory(from: payload)
        if hasPendingGlucoseHistoryUpdate {
            publishGlucoseHistory()
        }
    }

    private func applyGlucoseHistory(from payload: [String: Any]) {
        let isDelta = payload[WatchMessageKeys.glucoseSyncBase] != nil

        if isDelta, isGlucoseDeltaSyncDisabled {
            requestGlucoseResync(.full, reason: "delta received while delta sync is disabled")
            return
        }

        switch glucoseHistory.merge(payload) {
        case .unchanged:
            return

        case .updated:
            hasPendingGlucoseHistoryUpdate = true
            pendingGlucoseResync = nil
            glucoseResyncAttempts = 0
            saveGlucoseHistory()

        case .updatedUnverified:
            hasPendingGlucoseHistoryUpdate = true
            pendingGlucoseResync = nil
            glucoseResyncAttempts = 0
            disableGlucoseDeltaSync(reason: "full glucose history does not match its own checksum")
            saveGlucoseHistory()

        case .mismatch:
            // Keep showing the merged readings while the full window is on its way.
            hasPendingGlucoseHistoryUpdate = true
            requestGlucoseResync(.full, reason: "merged glucose history does not match the phone's")

        case .needsBackfill:
            requestGlucoseResync(.backfill, reason: "glucose delta does not connect to the newest local reading")

        case let .needsFullHistory(reason):
            requestGlucoseResync(.full, reason: reason)
        }
    }

    // MARK: - Glucose history persistence

    private static let glucoseHistoryFileURL: URL? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("GlucoseHistory.plist")
    private static let glucoseHistoryFileQueue = DispatchQueue(label: "WatchState.glucoseHistoryFile", qos: .utility)

    private func saveGlucoseHistory() {
        guard let url = Self.glucoseHistoryFileURL, let data = glucoseHistory.encoded() else { return }
        Self.glucoseHistoryFileQueue.async {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
            } catch {
                Task { await WatchLogger.shared.log("⌚️ Saving glucose history failed: \(error)") }
            }
        }
    }

    private func restoreGlucoseHistory() {
        guard let url = Self.glucoseHistoryFileURL,
              let data = try? Data(contentsOf: url),
              let restored = WatchGlucoseHistory(data: data)
        else { return }

        glucoseHistory = restored
        publishGlucoseHistory()
        Task { await WatchLogger.shared.log("⌚️ Restored \(restored.readings.count) saved glucose readings") }
    }

    private func publishGlucoseHistory() {
        glucoseValues = glucoseHistory.readings.map { reading in
            (
                date: Date(timeIntervalSince1970: reading.timestamp),
                glucose: reading.glucose,
                color: reading.color.toColor() // Convert colorString to Color
            )
        }
        hasPendingGlucoseHistoryUpdate = false
    }

    private func disableGlucoseDeltaSync(reason: String) {
        guard !isGlucoseDeltaSyncDisabled else { return }
        isGlucoseDeltaSyncDisabled = true
        Task { await WatchLogger.shared.log("⌚️ Glucose delta sync disabled: \(reason)", force: true) }
    }

    private func requestGlucoseResync(_ resync: GlucoseResync, reason: String) {
        Task { await WatchLogger.shared.log("⌚️ Glucose history resync (\(resync)): \(reason)") }
        pendingGlucoseResync = max(pendingGlucoseResync ?? resync, resync)
        sendPendingGlucoseResync()
    }

    /// One request at a time. A request that couldn't be delivered waits for the next regular update
    /// request, which carries the pending resync too.
    private func sendPendingGlucoseResync() {
        guard pendingGlucoseResync != nil, !isGlucoseResyncInFlight else { return }
        guard glucoseResyncAttempts < Self.maxGlucoseResyncAttempts else {
            Task { await WatchLogger.shared.log("⌚️ Glucose history resync attempts exhausted; waiting for the next update") }
            return
        }

        glucoseResyncAttempts += 1
        isGlucoseResyncInFlight = true
        let sent = requestWatchStateUpdate { answered in
            self.isGlucoseResyncInFlight = false
            if answered {
                self.sendPendingGlucoseResync()
            }
        }
        if !sent {
            isGlucoseResyncInFlight = false
        }
    }

    func glucoseSyncRequestFields() -> [String: Any] {
        var fields: [String: Any] = [WatchMessageKeys.supportsGlucoseDelta: !isGlucoseDeltaSyncDisabled]
        guard !isGlucoseDeltaSyncDisabled, pendingGlucoseResync != .full,
              let since = glucoseHistory.newestTimestamp,
              let signature = glucoseHistory.signature
        else { return fields }

        fields[WatchMessageKeys.glucoseSince] = since
        fields[WatchMessageKeys.glucoseSignature] = signature
        return fields
    }

    func session(_: WCSession, didFinish _: WCSessionUserInfoTransfer, error: (any Error)?) {
        if let error = error {
            Task {
                await WatchLogger.shared.log("⌚️ transferUserInfo failed with error: \(error)")
                await WatchLogger.shared.log("⌚️ Saving logs to disk as fallback!")
                await WatchLogger.shared.persistLogsLocally()
            }
        }
    }

    /// Called when the reachability status of the paired iPhone changes
    /// Updates the local reachability status
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            Task {
                await WatchLogger.shared.log("⌚️ Watch reachability changed: \(session.isReachable)")
            }

            self.isReachable = session.isReachable

            if session.isReachable {
                self.forceConditionalWatchStateUpdate()

                // reset input amounts
                self.bolusAmount = 0
                self.carbsAmount = 0

                // reset auth progress
                self.confirmationProgress = 0
            }
        }
    }

    /// Conditionally triggers a watch state update if the last known update was too long ago or has never occurred.
    ///
    /// This method checks the `lastWatchStateUpdate` timestamp to determine how many seconds
    /// have elapsed since the last update under the following conditions
    ///  - If `lastWatchStateUpdate` is `nil` (meaning there has never been an update), or
    ///  - If more than 15 seconds have passed,
    ///
    /// it will request a new watch state update from the iPhone app and, if the request could be sent, show a syncing animation.
    private func forceConditionalWatchStateUpdate() {
        guard let lastUpdateTimestamp = lastWatchStateUpdate else {
            Task {
                await WatchLogger.shared.log("Forcing initial WatchState update")
            }

            // If there's no recorded timestamp, we must force a fresh update immediately.
            requestWatchStateUpdateWithSyncingAnimation()
            return
        }

        let now = Date().timeIntervalSince1970
        let secondsSinceUpdate = now - lastUpdateTimestamp
        Task {
            await WatchLogger.shared.log("Time since last update: \(secondsSinceUpdate) seconds")
        }

        // If more than 15 seconds have elapsed since the last update, force an(other) update.
        if secondsSinceUpdate > 15 {
            requestWatchStateUpdateWithSyncingAnimation()
            return
        }
    }

    private func requestWatchStateUpdateWithSyncingAnimation() {
        guard requestWatchStateUpdate() else { return }

        showSyncingAnimation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.syncingAnimationTimeout) {
            guard self.showSyncingAnimation, self.pendingData.isEmpty else { return }
            self.showSyncingAnimation = false
            Task {
                await WatchLogger.shared.log("⌚️ No WatchState answer from iPhone — hiding syncing animation")
            }
        }
    }

    /// Handles incoming messages that either contain an acknowledgement or fresh watchState data  (<15 min)
    private func processWatchMessage(_ message: [String: Any]) {
        DispatchQueue.main.async {
            // 1) Acknowledgment logic
            if let acknowledged = message[WatchMessageKeys.acknowledged] as? Bool,
               let ackMessage = message[WatchMessageKeys.message] as? String,
               let ackCodeRaw = message[WatchMessageKeys.ackCode] as? String,
               let ackCode = AcknowledgmentCode(rawValue: ackCodeRaw)
            {
                DispatchQueue.main.async {
                    self.showSyncingAnimation = false
                }

                Task {
                    await WatchLogger.shared.log("⌚️ Received acknowledgment: \(ackMessage), success: \(acknowledged)")
                }

                switch ackCode {
                case .savingCarbs:
                    self.isMealBolusCombo = true
                    self.mealBolusStep = .savingCarbs
                    self.showCommsAnimation = true
                    self.handleAcknowledgment(success: acknowledged, message: ackMessage, isFinal: false)
                case .enactingBolus:
                    self.isMealBolusCombo = true
                    self.mealBolusStep = .enactingBolus
                    self.showCommsAnimation = true
                    self.handleAcknowledgment(success: acknowledged, message: ackMessage, isFinal: false)
                case .comboComplete:
                    self.isMealBolusCombo = false
                    self.handleAcknowledgment(success: acknowledged, message: ackMessage, isFinal: true)
                default:
                    self.isMealBolusCombo = false
                    self.handleAcknowledgment(success: acknowledged, message: ackMessage, isFinal: true)
                }
            }

            // 2) Raw watchState data
            if message[WatchMessageKeys.watchState] != nil {
                self.acceptWatchStatePayload(message)
            }
        }
    }

    /// Accumulate new data, set isSyncing, and debounce final update
    private func scheduleUIUpdate(with newData: [String: Any]) {
        if let incomingTimestamp = newData[WatchMessageKeys.date] as? TimeInterval,
           let lastTimestamp = lastWatchStateUpdate,
           incomingTimestamp <= lastTimestamp
        {
            Task {
                await WatchLogger.shared.log("Skipping UI update — outdated WatchState (\(incomingTimestamp))")
            }
            return
        }

        // 1) Mark as syncing
        DispatchQueue.main.async {
            self.showSyncingAnimation = true
        }

        Task {
            await WatchLogger.shared.log("Merging new WatchState data with keys: \(newData.keys.joined(separator: ", "))")
        }

        // 2) Merge data into our pendingData
        pendingData.merge(newData) { _, newVal in newVal }

        // 3) Cancel any previous finalization
        finalizeWorkItem?.cancel()

        // 4) Create and schedule a new finalization
        let workItem = DispatchWorkItem { [self] in
            Task {
                await WatchLogger.shared.log("⏳ Debounced update fired")
            }
            self.finalizePendingData()
        }
        finalizeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    /// Applies all pending data to the watch state in one shot
    private func finalizePendingData() {
        guard !pendingData.isEmpty else {
            Task {
                await WatchLogger.shared.log("⚠️ finalizePendingData called with empty data")
            }

            // If we have no actual data, just end syncing
            DispatchQueue.main.async {
                self.showSyncingAnimation = false
            }
            return
        }

        Task {
            await WatchLogger.shared.log("⌚️ Finalizing pending data")
        }

        // Actually set your main UI properties here
        processRawDataForWatchState(pendingData)

        // Clear
        pendingData.removeAll()

        // Done - hide sync animation
        DispatchQueue.main.async {
            self.showSyncingAnimation = false
        }

        Task {
            await WatchLogger.shared.log("✅ Watch UI update complete")
        }
    }

    /// Updates the UI properties
    private func processRawDataForWatchState(_ message: [String: Any]) {
        Task {
            await WatchLogger.shared.log("Processing raw WatchState data with keys: \(message.keys.joined(separator: ", "))")
        }

        if let timestamp = message[WatchMessageKeys.date] as? TimeInterval {
            lastWatchStateUpdate = timestamp
            Task {
                await WatchLogger.shared.log("Updated lastWatchStateUpdate: \(timestamp)")
            }
        }

        if let currentGlucose = message[WatchMessageKeys.currentGlucose] as? String {
            self.currentGlucose = currentGlucose
        }

        if let currentGlucoseColorString = message[WatchMessageKeys.currentGlucoseColorString] as? String {
            self.currentGlucoseColorString = currentGlucoseColorString
        }

        if let trend = message[WatchMessageKeys.trend] as? String {
            self.trend = trend
        }

        if let delta = message[WatchMessageKeys.delta] as? String {
            self.delta = delta
        }

        if let iob = message[WatchMessageKeys.iob] as? String {
            self.iob = iob
        }

        if let cob = message[WatchMessageKeys.cob] as? String {
            self.cob = cob
        }

        if let lastLoopTime = message[WatchMessageKeys.lastLoopTime] as? String {
            self.lastLoopTime = lastLoopTime
        }

        if hasPendingGlucoseHistoryUpdate {
            publishGlucoseHistory()
        }

        if let minYAxisValue = message[WatchMessageKeys.minYAxisValue] {
            if let decimalValue = (minYAxisValue as? NSNumber)?.decimalValue {
                self.minYAxisValue = decimalValue
            }
        }

        if let maxYAxisValue = message[WatchMessageKeys.maxYAxisValue] {
            if let decimalValue = (maxYAxisValue as? NSNumber)?.decimalValue {
                self.maxYAxisValue = decimalValue
            }
        }

        if let overrideData = message[WatchMessageKeys.overridePresets] as? [[String: Any]] {
            overridePresets = overrideData.compactMap { data in
                guard let name = data["name"] as? String,
                      let isEnabled = data["isEnabled"] as? Bool
                else { return nil }
                return OverridePresetWatch(name: name, isEnabled: isEnabled)
            }
        }

        if let tempTargetData = message[WatchMessageKeys.tempTargetPresets] as? [[String: Any]] {
            tempTargetPresets = tempTargetData.compactMap { data in
                guard let name = data["name"] as? String,
                      let isEnabled = data["isEnabled"] as? Bool
                else { return nil }
                return TempTargetPresetWatch(name: name, isEnabled: isEnabled)
            }
        }

        if let maxBolusValue = message[WatchMessageKeys.maxBolus] {
            if let decimalValue = (maxBolusValue as? NSNumber)?.decimalValue {
                maxBolus = decimalValue
            }
        }

        if let maxCarbsValue = message[WatchMessageKeys.maxCarbs] {
            if let decimalValue = (maxCarbsValue as? NSNumber)?.decimalValue {
                maxCarbs = decimalValue
            }
        }

        if let maxFatValue = message[WatchMessageKeys.maxFat] {
            if let decimalValue = (maxFatValue as? NSNumber)?.decimalValue {
                maxFat = decimalValue
            }
        }

        if let maxProteinValue = message[WatchMessageKeys.maxProtein] {
            if let decimalValue = (maxProteinValue as? NSNumber)?.decimalValue {
                maxProtein = decimalValue
            }
        }

        if let bolusIncrement = message[WatchMessageKeys.bolusIncrement] {
            if let decimalValue = (bolusIncrement as? NSNumber)?.decimalValue {
                // limit minimum to 0.05 to avoid dealing with 0.025 increments
                self.bolusIncrement = max(decimalValue, 0.05)
            }
        }

        if let confirmBolusFaster = message[WatchMessageKeys.confirmBolusFaster] {
            if let booleanValue = confirmBolusFaster as? Bool {
                self.confirmBolusFaster = booleanValue
            }
        }

        if let showForecast = message[WatchMessageKeys.showForecastWatch] as? Bool {
            self.showForecast = showForecast
        }

        if let isForecastCone = message[WatchMessageKeys.isForecastCone] as? Bool {
            self.isForecastCone = isForecastCone
        }

        if let forecastPayload = message[WatchMessageKeys.forecastData] as? [String: Any] {
            if let startTimestamp = forecastPayload[WatchMessageKeys.forecastStartDate] as? TimeInterval {
                forecastStartDate = Date(timeIntervalSince1970: startTimestamp)
            }
            forecastConeMin = forecastPayload[WatchMessageKeys.forecastConeMin] as? [Double] ?? []
            forecastConeMax = forecastPayload[WatchMessageKeys.forecastConeMax] as? [Double] ?? []
            forecastLines = forecastPayload[WatchMessageKeys.forecastLines] as? [String: [Double]] ?? [:]
        }
    }
}
