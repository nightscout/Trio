
import SwiftUI

struct TidePoolStartView: View {
    @ObservedObject var state: Settings.StateModel

    var body: some View {
        Form {
            Section {
                Text("Tidepool")
                    .onTapGesture {
                        state.setupTidePool = true
                    }

            } header: {
                Text("Connect to Tidepool")
            } footer: {
                Text(
                    "When connected, uploading of carbs, bolus, basal and glucose from Trio to your Tidepool account is enabled. \n\nUse your Tidepool credentials to login. If you dont already have a Tidepool account, you can sign up for one on the login page."
                )
            }
        }
        .sheet(isPresented: $state.setupTidePool) {
            if let serviceUIType = state.serviceUIType,
               let pluginHost = state.provider.tidePoolManager.getTidePoolPluginHost()
            {
                if let serviceUI = state.provider.tidePoolManager.getTidePoolServiceUI() {
                    TidePoolSettingsView(
                        serviceUI: serviceUI,
                        serviceOnBoardDelegate: self.state,
                        serviceDelegate: self.state
                    )
                } else {
                    TidePoolSetupView(
                        serviceUIType: serviceUIType,
                        pluginHost: pluginHost,
                        serviceOnBoardDelegate: self.state,
                        serviceDelegate: self.state
                    )
                }
            }
        }
        .navigationTitle("Tidepool")
    }
}
