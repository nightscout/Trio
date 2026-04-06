import SwiftUI

struct WatchConfigPebbleView: View {
    @ObservedObject var state: WatchConfig.StateModel

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        List {
            Section(header: Text("Pebble Integration")) {
                Toggle("Enable Pebble", isOn: $state.pebbleEnabled)

                if state.pebbleEnabled {
                    HStack {
                        Text("API Port")
                        Spacer()
                        Text("\(state.pebblePort)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(state.pebbleRunning ? "Running" : "Stopped")
                            .foregroundColor(state.pebbleRunning ? .green : .secondary)
                    }
                }
            }.listRowBackground(Color.chart)

            if state.pebbleEnabled {
                Section(header: Text("Pending Commands")) {
                    NavigationLink("View Pending Requests") {
                        PebbleCommandConfirmationView(commandManager: state.pebbleCommandManager)
                    }
                }.listRowBackground(Color.chart)

                Section(header: Text("How It Works")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Runs a local HTTP server on this device", systemImage: "network")
                        Label("PebbleKit JS in the Rebble app polls for data", systemImage: "arrow.triangle.2.circlepath")
                        Label("Bolus/carb requests require iPhone confirmation", systemImage: "checkmark.shield")
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }.listRowBackground(Color.chart)
            }
        }
        .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Pebble")
        .navigationBarTitleDisplayMode(.automatic)
    }
}
