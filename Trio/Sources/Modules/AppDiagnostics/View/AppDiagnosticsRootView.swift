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
                                    HStack {
                                        Image(
                                            systemName: state
                                                .diagnosticsSharingOption == option ? "largecircle.fill.circle" : "circle"
                                        )
                                        .foregroundColor(state.diagnosticsSharingOption == option ? .accentColor : .secondary)
                                        .imageScale(.large)

                                        Text(option.displayName)
                                            .foregroundColor(.primary)

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
