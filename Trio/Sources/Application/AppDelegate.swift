import SwiftUI
import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject, UNUserNotificationCenterDelegate {
    /// Assigned by `TrioApp.loadServices()` once the Core Data stack is up.
    /// Resolving `TelemetryClient` constructs the APS/device graph, whose first
    /// pump/CGM save crashes if the persistent stores are not loaded yet — so
    /// this delegate never resolves it, and pre-init foreground transitions no-op.
    var telemetry: TelemetryClient?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Default to `true` if the key doesn't exist — Trio is opt-out, not opt-in.
        // Read before touching Firebase: an explicit opt-out means we never
        // configure it, so no component can queue or upload anything.
        let crashReportingEnabled: Bool = PropertyPersistentFlags.shared.crashlyticsSharingEnabled ?? true
        CrashReportingGate.configureAtLaunch(enabled: crashReportingEnabled)

        return true
    }

    /// Foreground-transition entry point for telemetry cadence. Re-evaluates
    /// the overdue window every time the user brings Trio to the foreground,
    /// since `scheduleRecurring`'s GCD timer doesn't fire while suspended.
    /// No-op if a send already landed within the last 24h.
    func applicationWillEnterForeground(_: UIApplication) {
        telemetry?.checkAndSendIfOverdue(reason: .foreground)
    }

    func application(
        _: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        debug(.remoteControl, "Received notification")

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: userInfo)
            let encryptedMessage = try JSONDecoder().decode(EncryptedPushMessage.self, from: jsonData)

            Task {
                do {
                    try await TrioRemoteControl.shared.handleRemoteNotification(encryptedData: encryptedMessage.encryptedData)
                    completionHandler(.newData)
                } catch {
                    debug(
                        .default,
                        "\(DebuggingIdentifiers.failed) failed to handle remote notification with error: \(error)"
                    )
                    completionHandler(.failed)
                }
            }
        } catch {
            debug(.remoteControl, "Error decoding push message shell: \(error)")
            completionHandler(.failed)
        }
    }

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()

        Task {
            do {
                try await TrioRemoteControl.shared.handleAPNSChanges(deviceToken: token)
            } catch {
                debug(
                    .remoteControl,
                    "\(DebuggingIdentifiers.failed) failed to register for remote notifications: \(error)"
                )
            }
        }
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        debug(.remoteControl, "Failed to register for remote notifications: \(error)")
    }
}
