import SwiftUI
import Swinject

extension AppDiagnostics {
    struct RootView: BaseView {
        let resolver: Resolver

        @State var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        @Environment(\.openURL) var openURL

        var body: some View {
            List {
                Section(
                    header: Text("Anonymized Data Sharing"),
                    content: {
                        VStack(alignment: .leading) {
                            ForEach(DiagnosticsSharingOption.allCases, id: \.self) { option in
                                Button(action: {
                                    state.diagnosticsSharingOption = option
                                }) {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(
                                            systemName: state
                                                .diagnosticsSharingOption == option ? "largecircle.fill.circle" : "circle"
                                        )
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
                                    .background(Color.chart.opacity(0.65))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding()
                        }
                        .onChange(of: state.diagnosticsSharingOption) {
                            state.applyDiagnostics()
                        }
                    }
                ).listRowBackground(Color.chart)

                Section {
                    NavigationLink("What's sent") { TelemetryPreviewView() }
                    NavigationLink("Privacy details") { TelemetryPrivacyView() }
                }.listRowBackground(Color.chart)

                Section {
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
                                    localized: "Crash reports include the app's state on crash, device, iOS and general system info, and a stack trace. They are sent to a Google Firebase Crashlytics project maintained by the Trio team."
                                )
                            )
                            BulletPoint(
                                String(
                                    localized: "Anonymous usage statistics include the app version and build, device and iOS version, which pump and CGM you have paired, and whether Nightscout, Tidepool, and Apple Health are configured (yes/no — no URLs or credentials). They are sent to a self-hosted Trio telemetry endpoint."
                                )
                            )
                            BulletPoint(
                                String(
                                    localized: "Trio does not collect any health related data, e.g. glucose readings, insulin rates or doses, meal data, therapy setting values, or similar."
                                )
                            )
                        }
                        Text(
                            "Use \"What's sent\" above to inspect the exact JSON payload before deciding."
                        )
                    }
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(Color.secondary)
                }.listRowBackground(Color.clear)
            }
            .listSectionSpacing(sectionSpacing)
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationBarTitle("App Diagnostics")
            .navigationBarTitleDisplayMode(.automatic)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Privacy Policy") {
                        if let url = URL(string: "https://github.com/nightscout/Trio/blob/dev/PRIVACY_POLICY.md") {
                            openURL(url)
                        } else {
                            debug(.default, "Invalid URL! Could not gracefully unwrap privacy policy link!")
                        }
                    }
                }
            }
        }
    }
}
