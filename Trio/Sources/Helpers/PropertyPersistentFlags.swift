//
//  PropertyPersistentFlags.swift
//  Trio
//
//  Created by Cengiz Deniz on 06.05.25.
//
import Foundation

/// Centralized store for app-wide persistent flags backed by property list (.plist) files.
///
/// This class uses the `@PersistedProperty` wrapper to store simple state flags such as
/// onboarding completion, diagnostics sharing preference, and the last cleanup timestamp.
///
/// All values are persisted independently in the app’s documents directory as `.plist` files,
/// and survive app restarts and reinstallations (unless the sandbox is cleared).
///
/// Accessed as a singleton via `PropertyPersistentFlags.shared`.
final class PropertyPersistentFlags {
    static let shared = PropertyPersistentFlags()

    @PersistedProperty(key: "onboardingCompleted") var onboardingCompleted: Bool?

    @PersistedProperty(key: "diagnosticsSharing") var diagnosticsSharingEnabled: Bool?

    @PersistedProperty(key: "lastCleanupDate") var lastCleanupDate: Date?

    // TODO: This flag can be deleted in March 2027. Check the commit for other places to cleanup.
    @PersistedProperty(key: "hasSeenFatProteinOrderChange") var hasSeenFatProteinOrderChange: Bool?

    // MARK: - Telemetry

    //
    // See Trio/Sources/Services/Telemetry/TelemetryClient.swift.
    // `telemetryEnabled` gates the anonymous-usage POST. `diagnosticsSharingEnabled`
    // remains the Crashlytics gate. Both flags `nil` means the user has not yet
    // chosen — used to surface the one-time migration sheet to existing users.
    @PersistedProperty(key: "telemetryEnabled") var telemetryEnabled: Bool?
    @PersistedProperty(key: "telemetryConsentDecisionMade") var telemetryConsentDecisionMade: Bool?
    @PersistedProperty(key: "telemetryLastSentAt") var telemetryLastSentAt: Date?
    @PersistedProperty(key: "telemetryLastSentSha") var telemetryLastSentSha: String?
    // Sliding 7-day window of cold-launch timestamps; count is sent as `coldLaunches7d`.
    @PersistedProperty(key: "telemetryColdLaunchTimes") var telemetryColdLaunchTimes: [Date]?
    // Stable per-install UUID. IDFV resets when the user removes all Trio-team apps;
    // this survives independently and is wiped only by deleting Trio itself.
    @PersistedProperty(key: "telemetryInstallId") var telemetryInstallId: String?

    // App Attest "give up" signal — set on a 403 from /api/attest/register, meaning
    // the server has rejected this app_id and there's no point retrying.
    @PersistedProperty(key: "telemetryAttestForbidden") var telemetryAttestForbidden: Bool?

    // Debug override for the telemetry server base URL. Empty/unset → use the
    // production constant in TelemetryClient. Surfaced as a hidden field in
    // App Diagnostics for local testing against a dev server.
    @PersistedProperty(key: "telemetryDebugServerURL") var telemetryDebugServerURL: String?
}
