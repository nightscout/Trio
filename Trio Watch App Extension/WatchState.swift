import Foundation
import SwiftUI
import WatchConnectivity

/// WatchState manages the communication between the Watch app and the iPhone app using WatchConnectivity.
/// It handles glucose data synchronization and sending treatment requests (bolus, carbs) to the phone.
@Observable final class WatchState: NSObject, WCSessionDelegate {
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

    var bolusProgress: Double = 0.0
    var activeBolusAmount: Double = 0.0
    var deliveredAmount: Double = 0.0
    var isBolusCanceled = false

    // Safety limits
    var maxBolus: Decimal = 10
    var maxCarbs: Decimal = 250
    var maxFat: Decimal = 250
    var maxProtein: Decimal = 250

    // Pump specific dosing increment
    var bolusIncrement: Decimal = 0.05
    var confirmBolusFaster: Bool = false

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

    var showBolusProgressOverlay: Bool {
        (!showAcknowledgmentBanner || !showCommsAnimation) && bolusProgress > 0 && bolusProgress < 1.0 && !isBolusCanceled
    }

    var recommendedBolus: Decimal = 0

    // Debouncing and batch processing helpers

    /// Temporary storage for new data arriving via WatchConnectivity.
    private var pendingData: [String: Any] = [:]

    /// Work item to schedule finalizing the pending data.
    private var finalizeWorkItem: DispatchWorkItem?

    /// A flag to tell the UI we’re still updating.
    var showSyncingAnimation: Bool = false

    var deviceType = WatchSize.current

    override init() {
        super.init()
        setupSession()
    }

    /// Configures the WatchConnectivity session if supported on the device
    private func setupSession() {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
            self.session = session
        } else {
            print("⌚️ WCSession is not supported on this device")
        }
    }

    // MARK: – Handle Acknowledgement Messages FROM Phone

    func handleAcknowledgment(success: Bool, message: String, isFinal: Bool = true) {
        if success {
            print("⌚️ Acknowledgment received: \(message)")
            acknowledgementStatus = .success
            acknowledgmentMessage = "\(message)"
        } else {
            print("⌚️ Acknowledgment failed: \(message)")
            DispatchQueue.main.async {
                self.showCommsAnimation = false // Hide progress animation
            }
            acknowledgementStatus = .failure
            acknowledgmentMessage = "\(message)"
        }

        if isFinal {
            showAcknowledgmentBanner = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.showAcknowledgmentBanner = false
                self.showSyncingAnimation = false // Just ensure this is 100% set to false
            }
        }
    }

    // MARK: - WCSessionDelegate

    /// Called when the session has completed activation
    /// Updates the reachability status and logs the activation state
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                print("⌚️ Watch session activation failed: \(error.localizedDescription)")
                return
            }

            if activationState == .activated {
                print("⌚️ Watch session activated with state: \(activationState.rawValue)")

                self.forceConditionalWatchStateUpdate()

                self.isReachable = session.isReachable

                print("⌚️ Watch isReachable after activation: \(session.isReachable)")
            }
        }
    }

    /// Handles incoming messages from the paired iPhone when Phone is in the foreground
    func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        print("⌚️ Watch received data: \(message)")

        // If the message has a nested "watchState" dictionary with date as TimeInterval
        if let watchStateDict = message[WatchMessageKeys.watchState] as? [String: Any],
           let timestamp = watchStateDict[WatchMessageKeys.date] as? TimeInterval
        {
            let date = Date(timeIntervalSince1970: timestamp)

            // Check if it's not older than 15 min
            if date >= Date().addingTimeInterval(-15 * 60) {
                print("⌚️ Handling watchState from \(date)")
                processWatchMessage(message)
            } else {
                print("⌚️ Received outdated watchState data (\(date))")
                DispatchQueue.main.async {
                    self.showSyncingAnimation = false
                }
            }
            return
        }

        // Else if the message is an "ack" at the top level
        // e.g. { "acknowledged": true, "message": "Started Temp Target...", "date": Date(...) }
        else if
            let acknowledged = message[WatchMessageKeys.acknowledged] as? Bool,
            let ackMessage = message[WatchMessageKeys.message] as? String
        {
            print("⌚️ Handling ack with message: \(ackMessage), success: \(acknowledged)")
            DispatchQueue.main.async {
                // For ack messages, we do NOT show “Syncing...”
                self.showSyncingAnimation = false
            }
            processWatchMessage(message)
            return

                    // Recommended bolus is also not part of the WatchState message, hence the extra condition here
        } else if
            let recommendedBolus = message[WatchMessageKeys.recommendedBolus] as? NSNumber
        {
            print("⌚️ Received recommended bolus: \(recommendedBolus)")

            DispatchQueue.main.async {
                self.recommendedBolus = recommendedBolus.decimalValue
                self.showBolusCalculationProgress = false
            }

            return

                    // Handle bolus progress updates
        } else if
            let timestamp = message[WatchMessageKeys.bolusProgressTimestamp] as? TimeInterval,
            let progress = message[WatchMessageKeys.bolusProgress] as? Double,
            let activeBolusAmount = message[WatchMessageKeys.activeBolusAmount] as? Double,
            let deliveredAmount = message[WatchMessageKeys.deliveredAmount] as? Double
        {
            let date = Date(timeIntervalSince1970: timestamp)

            // Check if it's not older than 5 min
            if date >= Date().addingTimeInterval(-5 * 60) {
                print("⌚️ Handling bolusProgress (sent at \(date))")
                DispatchQueue.main.async {
                    if !self.isBolusCanceled {
                        self.bolusProgress = progress
                        self.activeBolusAmount = activeBolusAmount
                        self.deliveredAmount = deliveredAmount
                    }
                }
            } else {
                print("⌚️ Received outdated bolus progress (sent at \(date))")
                DispatchQueue.main.async {
                    self.bolusProgress = 0
                    self.activeBolusAmount = 0
                }
            }
            return

                    // Handle bolus cancellation
        } else if
            message[WatchMessageKeys.bolusCanceled] as? Bool == true
        {
            DispatchQueue.main.async {
                self.bolusProgress = 0
                self.activeBolusAmount = 0
                self
                    .isBolusCanceled =
                    false /// Reset flag to ensure a bolus progress is also shown after canceling bolus from watch
            }
            return
        } else {
            print("⌚️ Faulty data. Skipping...")
            DispatchQueue.main.async {
                self.showSyncingAnimation = false
            }
        }
    }

    /// Handles incoming messages from the paired iPhone when Phone is in the background
    func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        print("⌚️ Watch received data: \(userInfo)")

        // If the message has a nested "watchState" dictionary with date as TimeInterval
        if let watchStateDict = userInfo[WatchMessageKeys.watchState] as? [String: Any],
           let timestamp = watchStateDict[WatchMessageKeys.date] as? TimeInterval
        {
            let date = Date(timeIntervalSince1970: timestamp)

            // Check if it's not older than 15 min
            if date >= Date().addingTimeInterval(-15 * 60) {
                print("⌚️ Handling watchState from \(date)")
                processWatchMessage(userInfo)
            } else {
                print("⌚️ Received outdated watchState data (\(date))")
                DispatchQueue.main.async {
                    self.showSyncingAnimation = false
                }
            }
            return
        }

        // Else if the message is an "ack" at the top level
        // e.g. { "acknowledged": true, "message": "Started Temp Target...", "date": Date(...) }
        else if
            let acknowledged = userInfo[WatchMessageKeys.acknowledged] as? Bool,
            let ackMessage = userInfo[WatchMessageKeys.message] as? String
        {
            print("⌚️ Handling ack with message: \(ackMessage), success: \(acknowledged)")
            DispatchQueue.main.async {
                // For ack messages, we do NOT show “Syncing...”
                self.showSyncingAnimation = false
            }
            processWatchMessage(userInfo)
            return

                    // Recommended bolus is also not part of the WatchState message, hence the extra condition here
        } else if
            let recommendedBolus = userInfo[WatchMessageKeys.recommendedBolus] as? NSNumber
        {
            print("⌚️ Received recommended bolus: \(recommendedBolus)")
            self.recommendedBolus = recommendedBolus.decimalValue
            showBolusCalculationProgress = false
            return

                    // Handle bolus progress updates
        } else if
            let timestamp = userInfo[WatchMessageKeys.bolusProgressTimestamp] as? TimeInterval,
            let progress = userInfo[WatchMessageKeys.bolusProgress] as? Double,
            let activeBolusAmount = userInfo[WatchMessageKeys.activeBolusAmount] as? Double,
            let deliveredAmount = userInfo[WatchMessageKeys.deliveredAmount] as? Double
        {
            let date = Date(timeIntervalSince1970: timestamp)

            // Check if it's not older than 5 min
            if date >= Date().addingTimeInterval(-5 * 60) {
                print("⌚️ Handling bolusProgress (sent at \(date))")
                DispatchQueue.main.async {
                    if !self.isBolusCanceled {
                        self.bolusProgress = progress
                        self.activeBolusAmount = activeBolusAmount
                        self.deliveredAmount = deliveredAmount
                    }
                }
            } else {
                print("⌚️ Received outdated bolus progress (sent at \(date))")
                DispatchQueue.main.async {
                    self.bolusProgress = 0
                    self.activeBolusAmount = 0
                }
            }
            return

                    // Handle bolus cancellation
        } else if
            userInfo[WatchMessageKeys.bolusCanceled] as? Bool == true
        {
            DispatchQueue.main.async {
                self.bolusProgress = 0
                self.activeBolusAmount = 0
            }
            return
        } else {
            print("⌚️ Faulty data. Skipping...")
            DispatchQueue.main.async {
                self.showSyncingAnimation = false
            }
        }
    }

    /// Called when the reachability status of the paired iPhone changes
    /// Updates the local reachability status
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            print("⌚️ Watch reachability changed: \(session.isReachable)")

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
    /// it will show a syncing animation and request a new watch state update from the iPhone app.
    private func forceConditionalWatchStateUpdate() {
        guard let lastUpdateTimestamp = lastWatchStateUpdate else {
            // If there's no recorded timestamp, we must force a fresh update immediately.
            showSyncingAnimation = true
            requestWatchStateUpdate()
            return
        }

        let now = Date().timeIntervalSince1970
        let secondsSinceUpdate = now - lastUpdateTimestamp

        // If more than 15 seconds have elapsed since the last update, force an(other) update.
        if secondsSinceUpdate > 15 {
            showSyncingAnimation = true
            requestWatchStateUpdate()
            return
        }
    }

    /// Handles incoming messages that either contain an acknowledgement or fresh watchState data  (<15 min)
    private func processWatchMessage(_ message: [String: Any]) {
        DispatchQueue.main.async {
            // 1) Acknowledgment logic
            if let acknowledged = message[WatchMessageKeys.acknowledged] as? Bool,
               let ackMessage = message[WatchMessageKeys.message] as? String
            {
                DispatchQueue.main.async {
                    self.showSyncingAnimation = false
                }

                print("⌚️ Received acknowledgment: \(ackMessage), success: \(acknowledged)")

                switch ackMessage {
                case "Saving carbs...":
                    self.isMealBolusCombo = true
                    self.mealBolusStep = .savingCarbs
                    self.showCommsAnimation = true
                    self.handleAcknowledgment(success: acknowledged, message: ackMessage, isFinal: false)
                case "Enacting bolus...":
                    self.isMealBolusCombo = true
                    self.mealBolusStep = .enactingBolus
                    self.showCommsAnimation = true
                    self.handleAcknowledgment(success: acknowledged, message: ackMessage, isFinal: false)
                case "Carbs and bolus logged successfully":
                    self.isMealBolusCombo = false
                    self.handleAcknowledgment(success: acknowledged, message: ackMessage, isFinal: true)
                default:
                    self.isMealBolusCombo = false
                    self.handleAcknowledgment(success: acknowledged, message: ackMessage, isFinal: true)
                }
            }

            // 2) Raw watchState data
            if let watchStateData = message[WatchMessageKeys.watchState] as? [String: Any] {
                self.scheduleUIUpdate(with: watchStateData)
            }
        }
    }

    /// Accumulate new data, set isSyncing, and debounce final update
    private func scheduleUIUpdate(with newData: [String: Any]) {
        // 1) Mark as syncing
        DispatchQueue.main.async {
            self.showSyncingAnimation = true
        }

        // 2) Merge data into our pendingData
        pendingData.merge(newData) { _, newVal in newVal }

        // 3) Cancel any previous finalization
        finalizeWorkItem?.cancel()

        // 4) Create and schedule a new finalization
        let workItem = DispatchWorkItem { [self] in
            self.finalizePendingData()
        }
        finalizeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    /// Applies all pending data to the watch state in one shot
    private func finalizePendingData() {
        guard !pendingData.isEmpty else {
            // If we have no actual data, just end syncing
            DispatchQueue.main.async {
                self.showSyncingAnimation = false
            }
            return
        }

        print("⌚️ Finalizing pending data: \(pendingData)")

        // Actually set your main UI properties here
        processRawDataForWatchState(pendingData)

        // Clear
        pendingData.removeAll()

        // Done - hide sync animation
        DispatchQueue.main.async {
            self.showSyncingAnimation = false
        }
    }

    /// Updates the UI properties
    private func processRawDataForWatchState(_ message: [String: Any]) {
        if let timestamp = message[WatchMessageKeys.date] as? TimeInterval {
            lastWatchStateUpdate = timestamp
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

        if let glucoseData = message[WatchMessageKeys.glucoseValues] as? [[String: Any]] {
            glucoseValues = glucoseData.compactMap { data in
                guard let glucose = data["glucose"] as? Double,
                      let timestamp = data["date"] as? TimeInterval,
                      let colorString = data["color"] as? String
                else { return nil }

                return (
                    Date(timeIntervalSince1970: timestamp),
                    glucose,
                    colorString.toColor() // Convert colorString to Color
                )
            }
            .sorted { $0.date < $1.date }
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

        if let bolusProgress = message[WatchMessageKeys.bolusProgress] as? Double {
            if !isBolusCanceled {
                self.bolusProgress = bolusProgress
            }
        }

        if let bolusWasCanceled = message[WatchMessageKeys.bolusCanceled] as? Bool, bolusWasCanceled {
            bolusProgress = 0
            activeBolusAmount = 0
        }

        if let maxBolusValue = message[WatchMessageKeys.maxBolus] {
            print("⌚️ Received maxBolus: \(maxBolusValue) of type \(type(of: maxBolusValue))")
            if let decimalValue = (maxBolusValue as? NSNumber)?.decimalValue {
                maxBolus = decimalValue
                print("⌚️ Converted maxBolus to: \(decimalValue)")
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
                self.bolusIncrement = decimalValue
            }
        }

        if let confirmBolusFaster = message[WatchMessageKeys.confirmBolusFaster] {
            if let booleanValue = confirmBolusFaster as? Bool {
                self.confirmBolusFaster = booleanValue
            }
        }
    }
}
