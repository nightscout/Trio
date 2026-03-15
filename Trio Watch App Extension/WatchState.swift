import Foundation
import SwiftUI
import WatchConnectivity
import WidgetKit

// MARK: - App Group Helper

/// Returns the App Group suite name for sharing data between Watch app and complications
private func getAppGroupSuiteName() -> String? {
    guard let bundleId = Bundle.main.bundleIdentifier else { return nil }
    // Bundle ID format: org.nightscout.TEAMID.trio.watchkitapp (or .watchkitapp.TrioWatchComplication)
    // App Group format: group.org.nightscout.TEAMID.trio.trio-app-group
    let components = bundleId.components(separatedBy: ".")
    // Find the base: org.nightscout.TEAMID.trio
    if let trioIndex = components.firstIndex(of: "trio"), trioIndex >= 3 {
        let base = components[0...trioIndex].joined(separator: ".")
        return "group.\(base).trio-app-group"
    }
    return nil
}

/// Shared UserDefaults for Watch app and complications
var sharedUserDefaults: UserDefaults? {
    guard let suiteName = getAppGroupSuiteName() else { return nil }
    return UserDefaults(suiteName: suiteName)
}

/// WatchState manages the communication between the Watch app and the iPhone app using WatchConnectivity.
/// It handles glucose data synchronization and sending treatment requests (bolus, carbs) to the phone.
@Observable final class WatchState: NSObject, WCSessionDelegate {
    // MARK: - Shared Instance

    /// Shared instance for background refresh access
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
    var tdd: String? = nil  // Total Daily Dose
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
        setupSession()
    }

    /// Configures the WatchConnectivity session if supported on the device
    private func setupSession() {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
            self.session = session
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

                self.forceConditionalWatchStateUpdate()

                self.isReachable = session.isReachable

                // Check applicationContext for any pending complication data
                let context = session.receivedApplicationContext
                if context["complicationUpdate"] as? Bool == true {
                    Task {
                        await WatchLogger.shared.log("⌚️ Found complication data in applicationContext on activation")
                    }
                    self.handleComplicationUpdate(context)
                }

                Task {
                    await WatchLogger.shared.log("⌚️ Watch isReachable after activation: \(session.isReachable)")
                }
            }
        }
    }

    /// Handles incoming messages from the paired iPhone when Phone is in the foreground
    func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        Task {
            await WatchLogger.shared.log("⌚️ Watch received data: \(message)")
        }

        // If the message has a nested "watchState" dictionary with date as TimeInterval
        if let watchStateDict = message[WatchMessageKeys.watchState] as? [String: Any],
           let timestamp = watchStateDict[WatchMessageKeys.date] as? TimeInterval
        {
            let date = Date(timeIntervalSince1970: timestamp)

            // Check if it's not older than 15 min
            if date >= Date().addingTimeInterval(-15 * 60) {
                Task {
                    await WatchLogger.shared.log("⌚️ Handling watchState from \(date)")
                }
                processWatchMessage(message)
            } else {
                Task {
                    await WatchLogger.shared.log("⌚️ Received outdated watchState data (\(date))")
                }
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
            let ackMessage = message[WatchMessageKeys.message] as? String,
            let ackCodeRaw = message[WatchMessageKeys.ackCode] as? String
        {
            Task {
                await WatchLogger.shared
                    .log("⌚️ Handling ack with message: \(ackMessage), success: \(acknowledged), ackCode: \(ackCodeRaw)")
            }
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
            Task {
                await WatchLogger.shared.log("⌚️ Received recommended bolus: \(recommendedBolus)")
            }

            DispatchQueue.main.async {
                self.recommendedBolus = recommendedBolus.decimalValue
                self.showBolusCalculationProgress = false
            }

            return
        } else {
            Task {
                await WatchLogger.shared.log("⌚️ Faulty data. Skipping...")
            }
            DispatchQueue.main.async {
                self.showSyncingAnimation = false
            }
        }
    }

    func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        // Check if this is a high-priority complication update from iPhone
        if userInfo["complicationUpdate"] as? Bool == true {
            Task {
                await WatchLogger.shared.log("⌚️ Received high-priority complication update")
            }
            handleComplicationUpdate(userInfo)
            return
        }

        guard let snapshot = WatchStateSnapshot(from: userInfo) else {
            Task {
                await WatchLogger.shared.log("⌚️ Invalid snapshot received", force: true)
            }
            return
        }

        let lastProcessed = WatchStateSnapshot.loadLatestDateFromDisk()

        guard snapshot.date > lastProcessed else {
            Task {
                await WatchLogger.shared.log("⌚️ Ignoring outdated or duplicate WatchState snapshot", force: true)
            }
            return
        }

        WatchStateSnapshot.saveLatestDateToDisk(snapshot.date)

        DispatchQueue.main.async {
            self.scheduleUIUpdate(with: snapshot.payload)
        }
    }

    /// Public method to update complication from applicationContext
    /// Called during background refresh to check for pending data
    func updateComplicationFromContext(_ context: [String: Any]) {
        handleComplicationUpdate(context)
    }

    /// Handles complication updates from iPhone
    /// This is called when the iPhone sends data via transferUserInfo
    private func handleComplicationUpdate(_ userInfo: [String: Any]) {
        Task {
            await WatchLogger.shared.log("📥 handleComplicationUpdate called with keys: \(userInfo.keys.joined(separator: ", "))")
        }

        let glucose = userInfo[WatchMessageKeys.currentGlucose] as? String ?? "--"
        let trend = userInfo[WatchMessageKeys.trend] as? String ?? ""
        let delta = userInfo[WatchMessageKeys.delta] as? String ?? "--"
        let iob = userInfo[WatchMessageKeys.iob] as? String
        let cob = userInfo[WatchMessageKeys.cob] as? String
        let tdd = userInfo[WatchMessageKeys.tdd] as? String
        let colorString = userInfo[WatchMessageKeys.currentGlucoseColorString] as? String ?? "#ffffff"
        let timestamp = userInfo[WatchMessageKeys.date] as? TimeInterval

        Task {
            await WatchLogger.shared.log("📥 Parsed: glucose=\(glucose), trend=\(trend), delta=\(delta), tdd=\(tdd ?? "nil"), timestamp=\(timestamp ?? 0)")
        }

        // Determine if urgent based on color
        let isUrgent = !isGlucoseColorInRange(colorString)

        // Create and save complication data
        let complicationData = GlucoseComplicationData(
            glucose: glucose,
            trend: trend.isEmpty ? "→" : trend,
            delta: delta,
            iob: iob,
            cob: cob,
            tdd: tdd,
            glucoseDate: timestamp.map { Date(timeIntervalSince1970: $0) },
            lastLoopDate: timestamp.map { Date(timeIntervalSince1970: $0) },
            isUrgent: isUrgent
        )

        complicationData.save()

        // Delay before reloading to ensure UserDefaults is synced
        // This is critical for WidgetKit to read the updated data
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            WidgetCenter.shared.reloadAllTimelines()
        }

        Task {
            await WatchLogger.shared.log("📊 Complication updated: \(glucose) \(trend)")
        }
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

    /// Called when applicationContext is received from iPhone
    /// This is more reliable than transferUserInfo as it persists
    func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // Check if this contains complication data
        if applicationContext["complicationUpdate"] as? Bool == true {
            Task {
                await WatchLogger.shared.log("⌚️ Received applicationContext with complication data")
            }
            handleComplicationUpdate(applicationContext)
        }
    }

    /// Called when the reachability status of the paired iPhone changes
    /// Updates the local reachability status
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            Task {
                await WatchLogger.shared.log("⌚️ Watch reachability changed: \(session.isReachable)")
            }

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
            Task {
                await WatchLogger.shared.log("Forcing initial WatchState update")
            }

            // If there's no recorded timestamp, we must force a fresh update immediately.
            showSyncingAnimation = true
            requestWatchStateUpdate()
            return
        }

        let now = Date().timeIntervalSince1970
        let secondsSinceUpdate = now - lastUpdateTimestamp
        Task {
            await WatchLogger.shared.log("Time since last update: \(secondsSinceUpdate) seconds")
        }

        // If more than 15 seconds have elapsed since the last update, force an(other) update.
        if secondsSinceUpdate > 15 {
            showSyncingAnimation = true
            requestWatchStateUpdate()
            return
        }
    }

    /// Handles incoming messages that either contain an acknowledgement or fresh watchState data  (<15 min)
    private func processWatchMessage(_ message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 1) Acknowledgment logic
            if let acknowledged = message[WatchMessageKeys.acknowledged] as? Bool,
               let ackMessage = message[WatchMessageKeys.message] as? String,
               let ackCodeRaw = message[WatchMessageKeys.ackCode] as? String,
               let ackCode = AcknowledgmentCode(rawValue: ackCodeRaw)
            {
                // Already on main queue, no need for nested dispatch
                self.showSyncingAnimation = false

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
            if let watchStateData = message[WatchMessageKeys.watchState] as? [String: Any] {
                self.scheduleUIUpdate(with: watchStateData)
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
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
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

        if let tdd = message[WatchMessageKeys.tdd] as? String {
            self.tdd = tdd
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

        // Update complications with new glucose data
        updateComplicationData()
    }

    // MARK: - Complication Updates

    /// Saves current glucose data to shared storage and triggers complication refresh
    private func updateComplicationData() {
        // Get glucose date from the most recent glucose value
        let glucoseDate = glucoseValues.last?.date

        // Determine if glucose is urgent (out of range) based on color
        // White (#ffffff) = in range, anything else = urgent
        let isUrgent = !isGlucoseColorInRange(currentGlucoseColorString)

        // Create complication data
        let complicationData = GlucoseComplicationData(
            glucose: currentGlucose,
            trend: trend ?? "→",
            delta: delta ?? "--",
            iob: iob,
            cob: cob,
            tdd: tdd,
            glucoseDate: glucoseDate,
            lastLoopDate: lastWatchStateUpdate.map { Date(timeIntervalSince1970: $0) },
            isUrgent: isUrgent
        )

        // Save to shared UserDefaults
        complicationData.save()

        // Delay before reloading to ensure UserDefaults is synced
        // This is critical for WidgetKit to read the updated data
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            WidgetCenter.shared.reloadAllTimelines()
        }

        Task {
            await WatchLogger.shared.log("📊 Updated complication data: \(currentGlucose) \(trend ?? "") urgent=\(isUrgent)")
        }
    }

    /// Checks if the glucose color indicates "in range"
    /// iPhone sends white (#ffffff) for in-range, colored for out-of-range
    private func isGlucoseColorInRange(_ colorString: String) -> Bool {
        let normalized = colorString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // White (#ffffff) means in range, anything else is out of range
        return normalized == "#ffffff" || normalized == "ffffff"
    }
}

// MARK: - Shared Complication Data (must match Trio Watch Complication)

/// Data structure for sharing glucose information with complications
struct GlucoseComplicationData: Codable {
    let glucose: String
    let trend: String
    let delta: String
    let iob: String?
    let cob: String?
    let tdd: String?  // Total Daily Dose
    let glucoseDate: Date?
    let lastLoopDate: Date?
    let isUrgent: Bool  // true when glucose is out of range (high/low)

    static let key = "complicationData"

    init(glucose: String, trend: String, delta: String, iob: String?, cob: String?, tdd: String? = nil, glucoseDate: Date?, lastLoopDate: Date?, isUrgent: Bool = false) {
        self.glucose = glucose
        self.trend = trend
        self.delta = delta
        self.iob = iob
        self.cob = cob
        self.tdd = tdd
        self.glucoseDate = glucoseDate
        self.lastLoopDate = lastLoopDate
        self.isUrgent = isUrgent
    }

    /// Saves the data to shared App Group UserDefaults for complication access
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            // Use shared App Group UserDefaults so complications can read it
            let appGroup = getAppGroupSuiteName()
            if let shared = sharedUserDefaults {
                shared.set(encoded, forKey: Self.key)
                shared.set(Date(), forKey: "lastUpdate")
                shared.synchronize() // Force immediate write for WidgetKit
                Task {
                    await WatchLogger.shared.log("💾 Saved complication data to App Group: \(appGroup ?? "nil")")
                }
            } else {
                Task {
                    await WatchLogger.shared.log("⚠️ sharedUserDefaults is nil! App Group: \(appGroup ?? "nil")")
                }
            }
            // Also save to standard for backwards compatibility
            UserDefaults.standard.set(encoded, forKey: Self.key)
            UserDefaults.standard.synchronize()
        }
    }

    /// Loads the data from shared App Group UserDefaults
    static func load() -> GlucoseComplicationData? {
        // Try shared App Group first
        if let shared = sharedUserDefaults,
           let data = shared.data(forKey: key),
           let decoded = try? JSONDecoder().decode(GlucoseComplicationData.self, from: data) {
            return decoded
        }
        // Fall back to standard UserDefaults
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(GlucoseComplicationData.self, from: data)
        else { return nil }
        return decoded
    }
}
