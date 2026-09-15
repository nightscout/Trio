import FirebaseCore
import FirebaseCrashlytics
import Foundation

/// Enforces the App Diagnostics opt-out for the Crashlytics data stream.
///
/// Trio is opt-out, not opt-in, so on an untouched install Firebase is
/// configured at launch and FirebaseSessions (a transitive dependency of
/// FirebaseCrashlytics) hands a session-start event to GoogleDataTransport.
/// That is intended. The problem this type solves is what happens *after* the
/// user opts out:
///
///   * `setCrashlyticsCollectionEnabled(false)` only gates *future* events. It
///     does not touch the batch GoogleDataTransport already wrote to disk, and
///     GDT retries queued events for up to seven days on its own timer — which
///     is why a connection to `firebaselogging-pa.googleapis.com` still shows up
///     in Apple's App Privacy Report minutes after switching sharing off.
///   * On every later launch, `FirebaseApp.configure()` would start the whole
///     stack again before anything consults the user's choice.
///
/// So opting out purges GDT's store, and subsequent launches skip Firebase
/// initialization entirely — no Firebase component exists to queue or upload.
enum CrashReportingGate {
    /// GoogleDataTransport's on-disk event store. Mirrors `GDTCORRootDirectory()`,
    /// which is `<container>/Library/Caches/google-sdks-events`.
    private static var transportStorageURL: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("google-sdks-events", isDirectory: true)
    }

    /// Launch-time entry point. Configures Firebase only when the user has not
    /// opted out; when they have, nothing is configured and any events left over
    /// from before the opt-out are dropped so a later re-opt-in can't flush them.
    static func configureAtLaunch(enabled: Bool) {
        guard enabled else {
            purgeQueuedTransportEvents()
            return
        }

        FirebaseApp.configure()

        // The docs say that changes to this don't take effect until
        // the next app boot, but this is fine since the app will need
        // to boot after a crash
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        Crashlytics.crashlytics().setCustomValue(Bundle.main.appDevVersion ?? "unknown", forKey: "app_dev_version")
    }

    /// Runtime entry point for the App Diagnostics setting.
    ///
    /// Turning sharing back on configures Firebase if `configureAtLaunch` skipped
    /// it, so the choice takes effect without waiting for a restart.
    static func setEnabled(_ enabled: Bool) {
        guard enabled else {
            // Firebase may never have been configured this launch; only reach for
            // Crashlytics if it exists, otherwise there is nothing to switch off.
            if FirebaseApp.app() != nil {
                Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
                Crashlytics.crashlytics().deleteUnsentReports()
            }
            purgeQueuedTransportEvents()
            return
        }

        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        Crashlytics.crashlytics().setCustomValue(Bundle.main.appDevVersion ?? "unknown", forKey: "app_dev_version")
    }

    /// Deletes GoogleDataTransport's queued events and batches.
    ///
    /// GDT exposes no public purge API, so this removes its cache directory
    /// outright. Safe to do at any point: `GDTCORRootDirectory()` recreates the
    /// directory on next access, and the only thing lost is unsent diagnostics —
    /// exactly what the user asked us to stop sending.
    static func purgeQueuedTransportEvents() {
        guard let transportStorageURL,
              FileManager.default.fileExists(atPath: transportStorageURL.path)
        else {
            return
        }

        do {
            try FileManager.default.removeItem(at: transportStorageURL)
            debug(.default, "Purged queued GoogleDataTransport events after diagnostics opt-out.")
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) failed to purge queued GoogleDataTransport events: \(error)"
            )
        }
    }
}
