import SwiftUI

struct DiagnosticsStepView: View {
    @Bindable var state: Onboarding.StateModel

    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Help us improve Trio. Pick how much you'd like to share — or opt out entirely.")
                .font(.headline)
                .padding(.horizontal)
                .multilineTextAlignment(.leading)

            ForEach(DiagnosticsSharingOption.allCases, id: \.self) { option in
                Button(action: {
                    state.updateDiagnosticsOption(to: option)
                }) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: state.diagnosticsSharingOption == option ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(state.diagnosticsSharingOption == option ? .accentColor : .secondary)
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
                    .background(Color.chart.opacity(0.65))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }

            NavigationLink {
                TelemetryPreviewView()
            } label: {
                Label("See exactly what's sent", systemImage: "doc.text.magnifyingglass")
                    .font(.footnote)
            }
            .padding(.horizontal)

            Toggle(isOn: $state.hasAcceptedPrivacyPolicy) {
                HStack {
                    Text("I have read and accept the")
                    Button("Privacy Policy") {
                        if let url = URL(string: "https://github.com/nightscout/Trio/blob/dev/PRIVACY_POLICY.md") {
                            openURL(url)
                        } else {
                            debug(.default, "Invalid URL! Could not gracefully unwrap privacy policy link!")
                        }
                    }
                    .foregroundColor(.accentColor)
                    .underline()
                }
                .font(.footnote)
                .bold()
            }
            .toggleStyle(CheckboxToggleStyle(tint: Color.accentColor))
            .padding(.horizontal)
            .disabled(state.diagnosticsSharingOption == .disabled)
            .opacity(state.diagnosticsSharingOption == .disabled ? 0.35 : 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("Why does Trio collect this data?").bold()
                VStack(alignment: .leading, spacing: 4) {
                    BulletPoint(
                        String(
                            localized: "App diagnostic insights — based on crash reports only — help us enhance app stability, ensure safety for all users, and quickly identify and resolve critical issues."
                        )
                    )
                    BulletPoint(
                        String(
                            localized: "Crash reports include the app's state on crash, device, iOS info, and a stack trace. They are sent to Google Firebase Crashlytics, maintained by the Trio team."
                        )
                    )
                    BulletPoint(
                        String(
                            localized: "Anonymous usage statistics include the app version, your device and iOS version, your paired pump and CGM, and whether Nightscout, Tidepool, and Apple Health are configured (yes/no). No URLs, tokens, or credentials are included."
                        )
                    )
                    BulletPoint(
                        String(
                            localized: "Trio never collects glucose readings, insulin rates or doses, meal data, therapy setting values, or any other health information."
                        )
                    )
                }
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal)
            .font(.footnote)
            .foregroundStyle(Color.secondary)
        }
        .onAppear {
            state.syncDiagnosticsOptionFromStorage()
        }
    }
}
