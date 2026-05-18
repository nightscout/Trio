import FirebaseCrashlytics
import SwiftUI

/// One-shot sheet shown on first foreground for users who completed onboarding
/// before telemetry existed. Mirrors the onboarding `DiagnosticsStepView`
/// chooser but is presented standalone, with a Privacy-Policy acceptance gate
/// and no "skip" path — the user must explicitly pick one of the three options.
///
/// Once dismissed, `telemetryConsentDecisionMade` is set to `true` so the sheet
/// never re-appears for this install.
struct TelemetryMigrationSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var selectedOption: DiagnosticsSharingOption = .full
    // User already accepted the Privacy Policy during onboarding. This toggle
    // is a re-acknowledgment that the policy has been updated to cover the new
    // telemetry section — pre-checked so Continue works out of the box; users
    // who want to read the updated policy can uncheck and tap the link.
    @State private var hasAcceptedPrivacyPolicy: Bool = false

    var onDecision: (() -> Void)?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Help us improve Trio")
                        .font(.title2)
                        .bold()

                    Text(
                        "Until now, Trio could only sent crash reports. You can now also share anonymous usage statistics — things like your iPhone and iOS version, and which pump and CGM you have paired. This helps the Trio team prioritize what to fix and improve next."
                    )
                    .font(.subheadline)

                    Text(
                        "Your glucose data, therapy settings, credentials, and logs always stay on your device. Pick what you'd like to share — you can change this any time in Settings → App Diagnostics."
                    )
                    .font(.footnote)
                    .foregroundColor(.secondary)

                    ForEach(DiagnosticsSharingOption.allCases, id: \.self) { option in
                        Button(action: {
                            selectedOption = option
                        }) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: selectedOption == option ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(selectedOption == option ? .accentColor : .secondary)
                                    .imageScale(.large)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.displayName)
                                        .foregroundColor(.primary)
                                        .bold()
                                    Text(option.caption)
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }

                    Toggle(isOn: $hasAcceptedPrivacyPolicy) {
                        HStack {
                            Text("I have read and accept the")
                            Button("Privacy Policy") {
                                if let url = URL(string: "https://github.com/nightscout/Trio/blob/dev/PRIVACY_POLICY.md") {
                                    openURL(url)
                                }
                            }
                            .foregroundColor(.accentColor)
                            .underline()
                        }
                        .font(.footnote)
                    }
                    .toggleStyle(CheckboxToggleStyle(tint: Color.accentColor))
                    .disabled(selectedOption == .disabled)
                    .opacity(selectedOption == .disabled ? 0.35 : 1)

                    NavigationLink {
                        TelemetryPreviewView()
                    } label: {
                        Label("See exactly what's sent", systemImage: "doc.text.magnifyingglass")
                    }
                    .padding(.top, 4)
                }
                .padding()

                Spacer()

                Button {
                    confirm()
                } label: {
                    Text("Confirm").bold().frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedOption != .disabled && !hasAcceptedPrivacyPolicy)
                .padding(.top)
                .padding(.horizontal)
            }
            .navigationTitle("Improved Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text("NEW")
                            .font(.caption2)
                            .bold()
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                        Text("Improved Diagnostics")
                            .font(.headline)
                    }
                }
            }
            .interactiveDismissDisabled(true)
        }
    }

    private func confirm() {
        let wasTelemetryOn = PropertyPersistentFlags.shared.telemetryEnabled == true
        PropertyPersistentFlags.shared.diagnosticsSharingEnabled = selectedOption.crashlyticsEnabled
        PropertyPersistentFlags.shared.telemetryEnabled = selectedOption.telemetryEnabled
        PropertyPersistentFlags.shared.telemetryConsentDecisionMade = true
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(selectedOption.crashlyticsEnabled)

        if selectedOption.telemetryEnabled, !wasTelemetryOn {
            TelemetryClient.shared.scheduleRecurring()
            Task.detached { await TelemetryClient.shared.maybeSend() }
        }

        onDecision?()
        dismiss()
    }
}
