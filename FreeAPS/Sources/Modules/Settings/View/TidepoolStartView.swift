
import SwiftUI

struct TidepoolStartView: View {
    @ObservedObject var state: Settings.StateModel

    var body: some View {
        Form {
            Section(
                header: Text("Connect to Tidepool"),
                footer: VStack(alignment: .leading, spacing: 2) {
                    Text(
                        "When connected, uploading of carbs, bolus, basal and glucose from Trio to your Tidepool account is enabled."
                    )
                    Text(
                        "\nUse your Tidepool credentials to login. If you dont already have a Tidepool account, you can sign up for one on the login page."
                    )
                }
            )
                {
                    Button("Connect to Tidepool") { state.setupTidepool = true }
                }
                .navigationTitle("Tidepool")
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
    }
}
