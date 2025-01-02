import Foundation
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
    var trend: String? = ""
    var delta: String? = ""
    var glucoseValues: [(date: Date, glucose: Double)] = []

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
    ///   - isExternal: Indicates if the bolus is from an external source
    func sendBolusRequest(_ amount: Decimal, isExternal: Bool) {
        guard let session = session, session.isReachable else { return }

        let message: [String: Any] = [
            "bolus": amount,
            "isExternal": isExternal
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("Error sending bolus request: \(error.localizedDescription)")
        }
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

            print("⌚️ Watch session activated with state: \(activationState.rawValue)")
            self.isReachable = session.isReachable
            print("⌚️ Watch isReachable after activation: \(session.isReachable)")
        }
    }

    /// Handles incoming messages from the paired iPhone
    /// Updates local glucose data, trend, and delta information
    func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        print("⌚️ Watch received message: \(message)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let currentGlucose = message["currentGlucose"] as? String {
                self.currentGlucose = currentGlucose
            }

            if let trend = message["trend"] as? String {
                self.trend = trend
            }

            if let delta = message["delta"] as? String {
                self.delta = delta
            }

            if let glucoseData = message["glucoseValues"] as? [[String: Any]] {
                self.glucoseValues = glucoseData.compactMap { data in
                    guard let glucose = data["glucose"] as? Double,
                          let timestamp = data["date"] as? TimeInterval
                    else { return nil }

                    return (Date(timeIntervalSince1970: timestamp), glucose)
                }
                .sorted { $0.date < $1.date }
            }
        }
    }

    /// Called when the reachability status of the paired iPhone changes
    /// Updates the local reachability status
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            print("⌚️ Watch reachability changed: \(session.isReachable)")
        }
    }
}
