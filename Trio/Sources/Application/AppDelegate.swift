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
        let crashReportingEnabled: Bool = PropertyPersistentFlags.shared.diagnosticsSharingEnabled ?? true

        // The docs say that changes to this don't take effect until
        // the next app boot, but this is fine since the app will need
        // to boot after a crash
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(crashReportingEnabled)
        Crashlytics.crashlytics().setCustomValue(Bundle.main.appDevVersion ?? "unknown", forKey: "app_dev_version")

        return true
    }

    func application(
        _: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        debug(.remoteControl, "Received notification")

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: userInfo)
            let pushMessage = try JSONDecoder().decode(PushMessage.self, from: jsonData)

            Task {
                do {
                    try await TrioRemoteControl.shared.handleRemoteNotification(pushMessage: pushMessage)
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
            debug(.remoteControl, "Error decoding push message: \(error)")
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
