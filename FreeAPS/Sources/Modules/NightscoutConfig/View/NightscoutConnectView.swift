import SwiftUI

struct NightscoutConnectView: View {
    @ObservedObject var state: NightscoutConfig.StateModel
    @State private var portFormater: NumberFormatter

    init(state: NightscoutConfig.StateModel) {
        self.state = state
        portFormater = NumberFormatter()
        portFormater.allowsFloats = false
    }

    var body: some View {
        Form {
            Section {
                TextField("URL", text: $state.url)
                    .disableAutocorrection(true)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                SecureField("API secret", text: $state.secret)
                    .disableAutocorrection(true)
                    .autocapitalization(.none)
                    .textContentType(.password)
                    .keyboardType(.asciiCapable)
                if !state.message.isEmpty {
                    Text(state.message)
                }
                if state.connecting {
                    HStack {
                        Text("Connecting...")
                        Spacer()
                        ProgressView()
                    }
                }
            }
            Section {
                Button("Connect to Nightscout") { state.connect() }
                    .disabled(state.url.isEmpty || state.connecting)
                Button("Delete") { state.delete() }.foregroundColor(.red).disabled(state.connecting)
            }
            Section {
                Button("Open Nightscout") {
                    UIApplication.shared.open(URL(string: state.url)!, options: [:], completionHandler: nil)
                }
                .disabled(state.url.isEmpty || state.connecting)
            }
            Section {
                Toggle("Use local glucose server", isOn: $state.useLocalSource)
                HStack {
                    Text("Port")
                    DecimalTextField("", value: $state.localPort, formatter: portFormater)
                }
            } header: { Text("Local glucose source") }
        }
        .navigationTitle("Connect")
    }
}
