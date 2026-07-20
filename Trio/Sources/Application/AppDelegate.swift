import FirebaseCore
import FirebaseCrashlytics
import SwiftUI
import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject, UNUserNotificationCenterDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        FirebaseApp.configure()

        // Default to `true` if the key doesn't exist
        let crashReportingEnabled: Bool = PropertyPersistentFlags.shared.crashlyticsSharingEnabled ?? true

        // The docs say that changes to this don't take effect until
        // the next app boot, but this is fine since the app will need
        // to boot after a crash
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(crashReportingEnabled)
        Crashlytics.crashlytics().setCustomValue(Bundle.main.appDevVersion ?? "unknown", forKey: "app_dev_version")

        // Telemetry: record this cold launch into the sliding 7-day window,
        // then drive cadence via three layered triggers — listed below in
        // priority of reliability:
        //
        //   1. SHA-change ping: build updated since last send. Awaited so
        //      the lastSentAt stamp is fresh before the overdue check.
        //   2. checkAndSendIfOverdue: covers the regular cold launch on the
        //      same build when >24h has passed since the last successful
        //      send. Together with the foreground-transition hook below
        //      (`applicationWillEnterForeground`), this keeps daily pings
        //      flowing on iOS.
        //   3. scheduleRecurring: best-effort fallback for the rare case
        //      where the app stays foregrounded for a full 24h.
        TelemetryClient.shared.recordColdLaunch()
        Task.detached {
            if TelemetryClient.shared.buildShaChangedSinceLastSend() {
                await TelemetryClient.shared.maybeSend()
            }
            TelemetryClient.shared.scheduleRecurring()
            TelemetryClient.shared.checkAndSendIfOverdue()
        }

        return true
    }

    /// Foreground-transition entry point for telemetry cadence. Re-evaluates
    /// the overdue window every time the user brings Trio to the foreground,
    /// since `scheduleRecurring`'s GCD timer doesn't fire while suspended.
    /// No-op if a send already landed within the last 24h.
    func applicationWillEnterForeground(_: UIApplication) {
        TelemetryClient.shared.checkAndSendIfOverdue()
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
