import SwiftUI

struct NightscoutConnectView: View {
    @ObservedObject var state: NightscoutConfig.StateModel
    @State private var portFormatter: NumberFormatter

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    init(state: NightscoutConfig.StateModel) {
        self.state = state
        portFormatter = NumberFormatter()
        portFormatter.allowsFloats = false
        portFormatter.usesGroupingSeparator = false
    }

    var body: some View {
        List {
            Section(
                header: Text("Connect to Nightscout"),
                content: {
                    HStack {
                        TextField("URL", text: $state.url)
                            .disableAutocorrection(true)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                        if state.message.isNotEmpty && !state.isValidURL {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    SecureField("API secret", text: $state.secret)
                        .disableAutocorrection(true)
                        .autocapitalization(.none)
                        .textContentType(.password)
                        .keyboardType(.asciiCapable)
                    if state.message.isNotEmpty {
                        Text(state.message)
                    }
                    if state.connecting {
                        HStack {
                            Text("Connecting...")
                            Spacer()
                            ProgressView()
                        }
                    }

                    if !state.isConnectedToNS {
                        Button {
                            state.connect()
                        } label: {
                            Text("Connect to Nightscout")
                                .font(.title3) }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .buttonStyle(.bordered)
                            .disabled(state.url.isEmpty && state.connecting)
                    } else {
                        Button(role: .destructive) {
                            state.delete()
                        } label: {
                            Text("Disconnect and Remove")
                                .font(.title3)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .buttonStyle(.bordered)
                        .tint(Color.loopRed)
                    }
                }
            ).listRowBackground(Color.chart)

            if state.isConnectedToNS {
                Section {
                    Button {
                        UIApplication.shared.open(URL(string: state.url)!, options: [:], completionHandler: nil)
                    }
                    label: { Label("Open Nightscout", systemImage: "waveform.path.ecg.rectangle").font(.title3).padding() }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .buttonStyle(.bordered)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listSectionSpacing(sectionSpacing)
        .navigationTitle("Connect")
        .navigationBarTitleDisplayMode(.automatic)
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
    }
}
