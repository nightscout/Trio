
import SwiftUI
import Swinject

struct TidepoolStartView: BaseView {
    let resolver: Resolver
    @ObservedObject var state: Settings.StateModel

    @State private var shouldDisplayHint: Bool = false
    @State var hintDetent = PresentationDetent.large
    @State private var decimalPlaceholder: Decimal = 0.0
    @State private var booleanPlaceholder: Bool = false

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
                                        Text("Connected to Tidepool").font(.title3)
                                        ZStack {
                                            Image(systemName: "network")
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green).font(.caption2)
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

            if state.serviceUIType != nil {
                Section {
                    Toggle(isOn: $state.uploadPumpSettings) {
                        Text("Include Therapy Settings")
                    }
                    .disabled(state.provider.tidepoolManager.getTidepoolServiceUI() == nil)

                    Text(
                        "Uploads your therapy settings (basal schedules, carb ratios, insulin sensitivities, blood glucose targets, and override presets) to Tidepool. This helps your care team see your therapy configuration alongside your data."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
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
                    "When connected, uploading of carbs, bolus, basal and glucose from Trio to your Tidepool account is enabled.\n\nYou can optionally enable therapy settings upload (basal schedules, carb ratios, insulin sensitivities, blood glucose targets, and override presets) by tapping the Connected to Tidepool button and enabling the \"Include Therapy Settings\" toggle. This helps your care team see your therapy configuration alongside your data.\n\nUse your Tidepool credentials to login. If you dont already have a Tidepool account, you can sign up for one on the login page."
                ),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
        .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Tidepool")
        .navigationBarTitleDisplayMode(.automatic)
        .onAppear(perform: configureView)
    }
}
