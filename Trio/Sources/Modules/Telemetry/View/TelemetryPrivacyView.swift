import SwiftUI

/// In-app summary so users don't have to leave the app to understand what is
/// collected. Mirrors the relevant section in PRIVACY_POLICY.md.
struct TelemetryPrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    Text("Endpoint")
                        .font(.headline)
                    Text(
                        "Once a day (or after a new build is installed), Trio sends a small JSON object to a self-hosted endpoint maintained by the Trio team. No third-party analytics service is involved."
                    )
                }

                Group {
                    Text("What is sent")
                        .font(.headline)
                    Text(
                        "App version, build date, branch, and commit SHA; whether this is a TestFlight build; an Apple-supplied per-vendor identifier (IDFV) and a per-install UUID; hardware identifier (e.g. iPhone15,2); platform and iOS version; the paired pump model (when a pump is configured); the paired CGM type and model (when a CGM is configured); whether Nightscout, Tidepool, and Apple Health are configured (yes/no — no URLs, tokens, or credentials); and a few preference flags (units, closed-loop on/off, Live Activity, calendar integration). A rolling cold-launch count is included. The full JSON is visible under App Diagnostics → What's sent."
                    )
                }

                Group {
                    Text("What stays on your device")
                        .font(.headline)
                    Text(
                        "All glucose, insulin, and carb data. All therapy settings (basal, ISF, carb ratio, glucose targets). Your Nightscout URL and API token. Your Tidepool credentials. Remote-command secrets and APNS keys. Location data. Logs are never sent automatically; sharing them remains a user-initiated flow."
                    )
                }

                Group {
                    Text("Frequency")
                        .font(.headline)
                    Text(
                        "Once every 24 hours while the app is running, plus once after installing a new build."
                    )
                }

                Group {
                    Text("Opt out")
                        .font(.headline)
                    Text(
                        "Crash reporting and anonymous usage telemetry are enabled by default. Use the diagnostics-sharing chooser above to opt out: pick \"Crash Reports Only\" to keep crash reporting but disable telemetry, or \"Disable Sharing\" to turn off both. Changes take effect immediately."
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
