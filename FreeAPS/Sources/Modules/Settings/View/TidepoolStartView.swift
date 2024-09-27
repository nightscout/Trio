
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
    var color: LinearGradient {
        colorScheme == .dark ? LinearGradient(
            gradient: Gradient(colors: [
                Color.bgDarkBlue,
                Color.bgDarkerDarkBlue
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
            :
            LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                startPoint: .top,
                endPoint: .bottom
            )
    }

    var body: some View {
        Form {
            Section(
                header: Text("Tidepool Integration"),
                content:
                {
                    VStack {
                        Button {
                            state.setupTidepool.toggle()
                        }
                        label: { Text("Connect to Tidepool").font(.title3) }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .buttonStyle(.bordered)

                        HStack(alignment: .top) {
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
                hintText: "When connected, uploading of carbs, bolus, basal and glucose from Trio to your Tidepool account is enabled.\n\nUse your Tidepool credentials to login. If you dont already have a Tidepool account, you can sign up for one on the login page.",
                sheetTitle: "Help"
            )
        }
        .scrollContentBackground(.hidden).background(color)
        .navigationTitle("Tidepool")
        .navigationBarTitleDisplayMode(.automatic)
        .onAppear(perform: configureView)
    }
}
