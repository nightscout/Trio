
import SwiftUI
import Swinject

struct TidepoolStartView: BaseView {
    let resolver: Resolver
    @ObservedObject var state: Settings.StateModel

    @State private var shouldDisplayHint: Bool = false
    @State var hintDetent = PresentationDetent.large
    @State private var decimalPlaceholder: Decimal = 0.0
    @State private var booleanPlaceholder: Bool = false

    /// Mirror of `TidepoolManager.healthPublisher`. Drives the connection
    /// indicator below — `getTidepoolServiceUI() != nil` only proves the
    /// service was once configured, not that it's still authenticated.
    @State private var tidepoolHealth: TidepoolHealth = .unknown

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        Form {
            Section(
                header: Text("Tidepool Integration"),
                content:
                {
                    VStack {
                        if let serviceUIType = state.serviceUIType,
                           let pluginHost = state.provider.tidepoolManager.getTidepoolPluginHost()
                        {
                            if let serviceUI = state.provider.tidepoolManager.getTidepoolServiceUI()
                            {
                                Button {
                                    state.setupTidepool.toggle()
                                }
                                label: {
                                    HStack {
                                        Text(connectionLabel).font(.title3)
                                        ZStack {
                                            Image(systemName: "network")
                                            Image(systemName: connectionIconName)
                                                .foregroundColor(connectionIconColor).font(.caption2)
                                                .offset(x: 9, y: 6)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .buttonStyle(.bordered)
                            } else {
                                Button {
                                    state.setupTidepool.toggle()
                                }
                                label: { Text("Connect to Tidepool").font(.title3) }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .buttonStyle(.bordered)
                            }
                        }

                        HStack(alignment: .center) {
                            Text("You can connect Trio to seamlessly upload and manage your diabetes data on Tidepool.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    shouldDisplayHint.toggle()
                                },
                                label: {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.top)
                    }.padding(.vertical)
                }
            ).listRowBackground(Color.chart)
        }
        .sheet(isPresented: $state.setupTidepool) {
            if let serviceUIType = state.serviceUIType,
               let pluginHost = state.provider.tidepoolManager.getTidepoolPluginHost()
            {
                if let serviceUI = state.provider.tidepoolManager.getTidepoolServiceUI() {
                    TidepoolSettingsView(
                        serviceUI: serviceUI,
                        serviceOnBoardDelegate: self.state,
                        serviceDelegate: self.state
                    )
                } else {
                    TidepoolSetupView(
                        serviceUIType: serviceUIType,
                        pluginHost: pluginHost,
                        serviceOnBoardDelegate: self.state,
                        serviceDelegate: self.state
                    )
                }
            }
        }
        .sheet(isPresented: $shouldDisplayHint) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint,
                hintLabel: "Connect to Tidepool",
                hintText: Text(
                    "Use your Tidepool credentials to log in. If you don't have a Tidepool account, you can sign up on the login page.\n\nWhen connected, Trio uploads your glucose, carb entries, insulin (bolus and basal), pump settings, and therapy settings to Tidepool.\n\nTherapy settings include basal schedules, carb ratios, insulin sensitivities, and glucose targets."
                ),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
        .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Tidepool")
        .navigationBarTitleDisplayMode(.automatic)
        .onAppear(perform: configureView)
        .onReceive(state.provider.tidepoolManager.healthPublisher) { newHealth in
            tidepoolHealth = newHealth
        }
    }

    /// Label shown next to the network icon when a Tidepool service is configured.
    /// Auth failures get an explicit re-login prompt; transient hiccups are
    /// surfaced but kept gentler so a flaky network doesn't alarm the user.
    private var connectionLabel: String {
        switch tidepoolHealth {
        case .healthy,
             .unknown:
            return String(localized: "Connected to Tidepool")
        case .authFailed:
            return String(localized: "Tidepool Auth Error — tap to re-login")
        case .transient:
            return String(localized: "Tidepool Sync Error")
        }
    }

    /// SF Symbol for the small status dot overlaid on the network icon.
    private var connectionIconName: String {
        switch tidepoolHealth {
        case .healthy,
             .unknown:
            return "checkmark.circle.fill"
        case .authFailed:
            return "xmark.circle.fill"
        case .transient:
            return "exclamationmark.circle.fill"
        }
    }

    private var connectionIconColor: Color {
        switch tidepoolHealth {
        case .healthy,
             .unknown:
            return .green
        case .authFailed:
            return .red
        case .transient:
            return .orange
        }
    }
}
