import Foundation
import SwiftUI
import WatchConnectivity

/// WatchState manages the communication between the Watch app and the iPhone app using WatchConnectivity.
/// It handles glucose data synchronization and sending treatment requests (bolus, carbs) to the phone.
@Observable final class WatchState: NSObject, WCSessionDelegate {
    // MARK: - Properties

    /// The WatchConnectivity session instance used for communication
    private var session: WCSession?
    /// Indicates if the paired iPhone is currently reachable
    var isReachable = false

    var currentGlucose: String = "--"
    var currentGlucoseColorString: String = "#ffffff"
    var trend: String? = ""
    var delta: String? = "--"
    var glucoseValues: [(date: Date, glucose: Double, color: Color)] = []
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
    var bolusAmount = 0.0
    var activeBolusAmount = 0.0
    var confirmationProgress = 0.0

    var bolusProgress: Double = 0.0
    var isBolusCanceled = false

    // Safety limits
    var maxBolus: Decimal = 10
    var maxCarbs: Decimal = 250
    var maxFat: Decimal = 250
    var maxProtein: Decimal = 250
    var maxIOB: Decimal = 0
    var maxCOB: Decimal = 120

    // Pump specific dosing increment
    var bolusIncrement: Decimal = 0.05

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
        (!showAcknowledgmentBanner || !showCommsAnimation || !showCommsAnimation) && bolusProgress > 0 && bolusProgress < 1.0 &&
            !isBolusCanceled
    }

    var recommendedBolus: Decimal = 0

    // Debouncing and batch processing helpers

    /// Temporary storage for new data arriving via WatchConnectivity.
    private var pendingData: [String: Any] = [:]

    /// Work item to schedule finalizing the pending data.
    private var finalizeWorkItem: DispatchWorkItem?

    /// A flag to tell the UI we’re still updating.
    var showSyncingAnimation: Bool = false

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

    // MARK: - Send Data to Phone

    /// Sends a bolus insulin request to the paired iPhone
    /// - Parameters:
    ///   - amount: The insulin amount to be delivered
    func sendBolusRequest(_ amount: Decimal) {
        guard let session = session, session.isReachable else { return }
        isBolusCanceled = false // Reset canceled state when starting new bolus
        activeBolusAmount = Double(truncating: amount as NSNumber) // Set active bolus amount

        let message: [String: Any] = [
            "bolus": amount
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("Error sending bolus request: \(error.localizedDescription)")
        }

        // Display pending communication animation
        showCommsAnimation = true
    }

    /// Sends a carbohydrate entry request to the paired iPhone
    /// - Parameters:
    ///   - amount: The amount of carbs in grams
    ///   - date: The timestamp for the carb entry (defaults to current time)
    func sendCarbsRequest(_ amount: Int, _ date: Date = Date()) {
        guard let session = session, session.isReachable else { return }

        let message: [String: Any] = [
            "carbs": amount,
            "date": date.timeIntervalSince1970
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("Error sending carbs request: \(error.localizedDescription)")
        }

        // Display pending communication animation
        showCommsAnimation = true
    }

    /// Sends a meal and bolus insulin combo request to the paired iPhone
    /// - Parameters:
    ///   - amount: The insulin amount to be delivered
    ///   - isExternal: Indicates if the bolus is from an external source
    func sendMealBolusComboRequest(carbsAmount _: Decimal, bolusAmount: Decimal, _ date: Date = Date()) {
        guard let session = session, session.isReachable else { return }

        let message: [String: Any] = [
            "bolus": bolusAmount,
            "carbs": bolusAmount,
            "date": date.timeIntervalSince1970
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("Error sending meal bolus combo request: \(error.localizedDescription)")
        }

        // Display pending communication animation
        showCommsAnimation = true
        isMealBolusCombo = true
    }

    func sendCancelOverrideRequest() {
        guard let session = session, session.isReachable else { return }

        let message: [String: Any] = [
            "cancelOverride": true
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("⌚️ Error sending cancel override request: \(error.localizedDescription)")
        }

        // Display pending communication animation
        showCommsAnimation = true
    }

    func sendActivateOverrideRequest(presetName: String) {
        guard let session = session, session.isReachable else { return }

        let message: [String: Any] = [
            "activateOverride": presetName
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("⌚️ Error sending activate override request: \(error.localizedDescription)")
        }

        // Display pending communication animation
        showCommsAnimation = true
    }

    func sendCancelTempTargetRequest() {
        guard let session = session, session.isReachable else { return }

        let message: [String: Any] = [
            "cancelTempTarget": true
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("⌚️ Error sending cancel temp target request: \(error.localizedDescription)")
        }

        // Display pending communication animation
        showCommsAnimation = true
    }

    func sendActivateTempTargetRequest(presetName: String) {
        guard let session = session, session.isReachable else { return }

        let message: [String: Any] = [
            "activateTempTarget": presetName
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("⌚️ Error sending activate temp target request: \(error.localizedDescription)")
        }

        // Display pending communication animation
        showCommsAnimation = true
    }

    func sendCancelBolusRequest() {
        isBolusCanceled = true

        guard let session = session, session.isReachable else { return }

        let message: [String: Any] = [
            "cancelBolus": true
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("Error sending cancel bolus request: \(error.localizedDescription)")
        }

        // Reset when cancelled
        bolusProgress = 0
        activeBolusAmount = 0

        // Display pending communication animation
        showCommsAnimation = true
    }

    func requestBolusRecommendation() {
        guard let session = session, session.isReachable else { return }

        let message: [String: Any] = [
            WatchMessageKeys.requestBolusRecommendation: true,
            WatchMessageKeys.carbs: carbsAmount
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("Error requesting bolus recommendation: \(error.localizedDescription)")
        }

        if bolusAmount == 0 {
            showBolusCalculationProgress = true
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
            acknowledgementStatus = .failure
            acknowledgmentMessage = "\(message)"
        }

        DispatchQueue.main.async {
            self.showCommsAnimation = false // Hide progress animation
            self.showSyncingAnimation = false // Just ensure this is 100% set to false
        }

        if isFinal {
            showAcknowledgmentBanner = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.showAcknowledgmentBanner = false
                self.showSyncingAnimation = false // Just ensure this is 100% set to false
            }
        }
    }

    func requestWatchStateUpdate() {
        guard let session = session, session.activationState == .activated else {
            print("⌚️ Session not activated, activating...")
            session?.activate()
            return
        }

        if session.isReachable {
            print("⌚️ Request an update for watch state from Trio iPhone app...")

            let message = [WatchMessageKeys.requestWatchUpdate: WatchMessageKeys.watchState]

            session.sendMessage(message, replyHandler: nil) { error in
                print("⌚️ Update request for fresh watch state data: \(error.localizedDescription)")
            }
        } else {
            print("⌚️ Phone not reachable for watch state update")
        }
    }

    private func processRawDataForWatchState(_ message: [String: Any]) {
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
//            return
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

        if let maxIOBValue = message[WatchMessageKeys.maxIOB] {
            if let decimalValue = (maxIOBValue as? NSNumber)?.decimalValue {
                maxIOB = decimalValue
            }
        }

        if let maxCOBValue = message[WatchMessageKeys.maxCOB] {
            if let decimalValue = (maxCOBValue as? NSNumber)?.decimalValue {
                maxCOB = decimalValue
            }
        }

        if let bolusIncrement = message[WatchMessageKeys.bolusIncrement] {
            if let decimalValue = (bolusIncrement as? NSNumber)?.decimalValue {
                self.bolusIncrement = decimalValue
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

            // the order here is probably not perfect and needsto be re-arranged
            if activationState == .activated {
                self.requestWatchStateUpdate()
            }

            print("⌚️ Watch session activated with state: \(activationState.rawValue)")

            self.isReachable = session.isReachable

            print("⌚️ Watch isReachable after activation: \(session.isReachable)")
        }
    }

    /// Handles incoming messages from the paired iPhone
    /// Updates local glucose data, trend, and delta information
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

        } else {
            print("⌚️ Faulty data. Skipping...")
            DispatchQueue.main.async {
                self.showSyncingAnimation = false
            }
        }
    }

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

        } else {
            print("⌚️ Faulty data. Skipping...")
            DispatchQueue.main.async {
                self.showSyncingAnimation = false
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
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

        // Done - but ensure this runs at least 2 sec, to avoid flickering
        DispatchQueue.main.async {
            self.showSyncingAnimation = false
        }
    }

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

            // 2) Bolus progress
            if let progress = message[WatchMessageKeys.bolusProgress] as? Double {
                if !self.isBolusCanceled {
                    self.bolusProgress = progress
                }
                DispatchQueue.main.async {
                    self.showSyncingAnimation = false
                }
            }

            // 3) Bolus cancellation
            if message[WatchMessageKeys.bolusCanceled] as? Bool == true {
                self.bolusProgress = 0
                self.activeBolusAmount = 0
                DispatchQueue.main.async {
                    self.showSyncingAnimation = false
                }
            }

            // 4) Recommended bolus
            if let recommendedBolus = message[WatchMessageKeys.recommendedBolus] as? NSNumber {
                self.recommendedBolus = recommendedBolus.decimalValue
                self.showBolusCalculationProgress = false
                DispatchQueue.main.async {
                    self.showSyncingAnimation = false
                }
            }

            // 5) Raw watchState data
            if let watchStateData = message[WatchMessageKeys.watchState] as? [String: Any] {
                self.scheduleUIUpdate(with: watchStateData)
            }
        }
    }

    /// Called when the reachability status of the paired iPhone changes
    /// Updates the local reachability status
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            print("⌚️ Watch reachability changed: \(session.isReachable)")

            if session.isReachable {
                // request fresh data from watch
                self.requestWatchStateUpdate()

                // reset input amounts
                self.bolusAmount = 0
                self.carbsAmount = 0
                // reset auth progress
                self.confirmationProgress = 0
            }
        }
    }
}
