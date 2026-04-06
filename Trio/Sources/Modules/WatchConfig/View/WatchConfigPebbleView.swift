import SwiftUI

struct WatchConfigPebbleView: View {
    @ObservedObject var state: WatchConfig.StateModel

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    @State private var pebblePortField: String = ""
    @FocusState private var portFieldFocused: Bool

    var body: some View {
        List {
            Section(
                header: Text("Pebble Integration"),
                content: {
                    Toggle("Enable Pebble", isOn: $state.pebbleEnabled)

                    if state.pebbleEnabled {
                        HStack(alignment: .firstTextBaseline) {
                            Text("API port")
                            Spacer()
                            TextField("1024–65535", text: $pebblePortField)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 56, maxWidth: 100)
                                .focused($portFieldFocused)
                                .onSubmit { commitPort() }
                            Button("Apply") { commitPort() }
                                .buttonStyle(.borderless)
                                .disabled(!isPortFieldValid)
                        }
                        HStack {
                            Text("Listen URL")
                            Spacer()
                            Text(verbatim: "http://127.0.0.1:\(state.pebblePort)")
                                .font(.footnote.monospaced())
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                        HStack {
                            Text("Status")
                            Spacer()
                            Text(state.pebbleRunning ? "Running" : "Stopped")
                                .foregroundColor(state.pebbleRunning ? .green : .secondary)
                        }
                    }
                }
            )
            .listRowBackground(Color.chart)

            if state.pebbleEnabled {
                WatchConfigPebbleEnabledSections(state: state)
            }
        }
        .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Pebble")
        .navigationBarTitleDisplayMode(.automatic)
        .onAppear {
            syncPortFieldFromState()
        }
        .onChange(of: state.pebblePort) { _, newValue in
            if !portFieldFocused {
                pebblePortField = String(newValue)
            }
        }
        .onChange(of: state.pebbleEnabled) { _, enabled in
            if enabled {
                syncPortFieldFromState()
            }
        }
    }

    private var isPortFieldValid: Bool {
        let digits = pebblePortField.filter(\.isNumber)
        guard let v = UInt16(digits), v >= 1024, v <= 65535 else { return false }
        return true
    }

    private func syncPortFieldFromState() {
        pebblePortField = String(state.pebblePort)
    }

    private func commitPort() {
        state.applyPebbleHTTPPort(from: pebblePortField)
        syncPortFieldFromState()
        portFieldFocused = false
    }
}

// MARK: - Subview (avoids List/Table Section overload ambiguity in Swift 6 archive builds)

private struct WatchConfigPebbleEnabledSections: View {
    @ObservedObject var state: WatchConfig.StateModel

    var body: some View {
        Section(
            header: Text("Connection test"),
            content: {
                Button {
                    Task { await state.runPebbleConnectionTest() }
                } label: {
                    HStack {
                        if state.isPebbleConnectionTestRunning {
                            ProgressView()
                        }
                        Text("Verify local API (HTTP)")
                    }
                }
                .disabled(state.isPebbleConnectionTestRunning)

                if let test = state.lastPebbleConnectionTest {
                    Text(test.message)
                        .font(.footnote)
                        .foregroundColor(test.success ? .green : .red)
                        .textSelection(.enabled)
                }

                if let safariURL = URL(string: "http://127.0.0.1:\(state.pebblePort)/") {
                    Link(destination: safariURL) {
                        Label("Open API page in Safari", systemImage: "safari")
                    }
                }

                Text(
                    "Safari must run on this same iPhone. A Mac or PC browser cannot reach 127.0.0.1 on the phone. "
                        + "Try the root URL for a short help page, or /health and /api/cgm for raw JSON."
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        )
        .listRowBackground(Color.chart)

        Section(
            header: Text("Pending Commands"),
            content: {
                NavigationLink("View Pending Requests") {
                    PebbleCommandConfirmationView(commandManager: state.pebbleCommandManager)
                }
            }
        )
        .listRowBackground(Color.chart)

        Section(
            header: Text("How It Works"),
            content: {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Runs a local HTTP server on this device", systemImage: "network")
                    Label("PebbleKit JS in the Rebble app polls for data", systemImage: "arrow.triangle.2.circlepath")
                    Label("Bolus/carb requests require iPhone confirmation", systemImage: "checkmark.shield")
                    Text(
                        "In the Pebble watchface settings, set Trio API Host to the same URL (including port). "
                            + "Change the port here if 8080 conflicts with another app."
                    )
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }
                .font(.footnote)
                .foregroundColor(.secondary)
            }
        )
        .listRowBackground(Color.chart)
    }
}
