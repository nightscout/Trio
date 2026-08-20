import SwiftUI
import Swinject

extension OpenSourceClinicConfigModule {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            Form {
                Section(
                    header: Text("opensource.clinic"),
                    content: {
                        Toggle("Enable Sync", isOn: $state.isEnabled)
                            .tint(.green)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Server URL")
                                .font(.headline)
                            TextField("https://api.opensource.clinic", text: $state.url)
                                .textContentType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("API Token")
                                .font(.headline)
                            SecureField("osc_device_...", text: $state.token)
                                .textContentType(.password)
                                .autocapitalization(.none)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sync Interval")
                                .font(.headline)
                            Picker("Interval", selection: $state.syncInterval) {
                                Text("5 min").tag(TimeInterval(300))
                                Text("10 min").tag(TimeInterval(600))
                                Text("15 min").tag(TimeInterval(900))
                                Text("30 min").tag(TimeInterval(1800))
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                ).listRowBackground(Color.chart)

                Section(
                    header: Text("Connection"),
                    content: {
                        Button {
                            Task { await state.testConnection() }
                        } label: {
                            HStack {
                                if state.isTesting {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                }
                                Text(state.isTesting ? "Testing..." : "Test Connection")
                            }
                        }
                        .disabled(state.isTesting || state.token.isEmpty)

                        if let result = state.testResult {
                            Text(result)
                                .foregroundColor(result.contains("successful") ? .green : .red)
                                .font(.caption)
                        }

                        Button {
                            Task { await state.syncNow() }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Sync Now")
                            }
                        }
                        .disabled(!state.isEnabled || state.token.isEmpty)

                        if let lastSync = state.lastSyncDate {
                            HStack {
                                Text("Last sync")
                                Spacer()
                                Text(lastSync, style: .relative)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                ).listRowBackground(Color.chart)

                Section(
                    header: Text("Help"),
                    content: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Connect Trio to opensource.clinic for AI-powered therapy analysis.")
                                .font(.footnote)
                            Text("Get your API token from the opensource.clinic dashboard under Settings → API Tokens.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                ).listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("opensource.clinic")
            .navigationBarTitleDisplayMode(.automatic)
            .onAppear(perform: configureView)
        }
    }
}
