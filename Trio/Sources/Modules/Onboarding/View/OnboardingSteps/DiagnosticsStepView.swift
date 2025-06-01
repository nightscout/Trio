import SwiftUI

struct DiagnosticsStepView: View {
    @Bindable var state: Onboarding.StateModel

    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("If you prefer not to share this anonymized data, you can opt-out of data sharing.")
                .font(.headline)
                .padding(.horizontal)
                .multilineTextAlignment(.leading)

            ForEach(DiagnosticsSharingOption.allCases, id: \.self) { option in
                Button(action: {
                    state.updateDiagnosticsOption(to: option)
                }) {
                    HStack {
                        Image(systemName: state.diagnosticsSharingOption == option ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(state.diagnosticsSharingOption == option ? .accentColor : .secondary)
                            .imageScale(.large)

                        Text(option.displayName)
                            .foregroundColor(.primary)

                        Spacer()
                    }
                    .padding()
                    .background(Color.chart.opacity(0.65))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }

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
                            localized: "App diagnostic insights help us enhance app stability, ensure safety for all users, and enable us to quickly identify and resolve critical issues."
                        )
                    )
                    BulletPoint(
                        String(
                            localized: "Trio collects the app's state on crash, device, iOS and general system info, and a stack trace."
                        )
                    )
                    BulletPoint(
                        String(
                            localized: "Trio does not collect any health related data, e.g. glucose readings, insulin rates or doses, meal data, setting values, or similar."
                        )
                    )
                    BulletPoint(
                        String(
                            localized: "Trio does not track any usage metrics or any other personal data about users other than the used iPhone model and iOS version."
                        )
                    )
                }
                Text(
                    "Diagnostics are sent to a Google Firebase Crashlytics project, which is securely maintained and accessed only by the Trio team."
                )
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
