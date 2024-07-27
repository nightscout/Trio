import SwiftUI

struct NightscoutConnectView: View {
    @ObservedObject var state: NightscoutConfig.StateModel
    @State private var portFormatter: NumberFormatter

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

    init(state: NightscoutConfig.StateModel) {
        self.state = state
        portFormatter = NumberFormatter()
        portFormatter.allowsFloats = false
        portFormatter.usesGroupingSeparator = false
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
            }.listRowBackground(Color.chart)

            Section {
                Button("Connect to Nightscout") { state.connect() }
                    .disabled(state.url.isEmpty || state.connecting)
                Button("Delete") { state.delete() }.foregroundColor(.red).disabled(state.connecting)
            }.listRowBackground(Color.chart)

            Section {
                Button("Open Nightscout") {
                    UIApplication.shared.open(URL(string: state.url)!, options: [:], completionHandler: nil)
                }
                .disabled(state.url.isEmpty || state.connecting)
            }.listRowBackground(Color.chart)

            Section {
                Toggle("Use local glucose server", isOn: $state.useLocalSource)
                HStack {
                    Text("Port")
                    TextFieldWithToolBar(
                        text: $state.localPort,
                        placeholder: "",
                        keyboardType: .numberPad,
                        numberFormatter: portFormatter,
                        allowDecimalSeparator: false
                    )
                }
            } header: { Text("Local glucose source") }.listRowBackground(Color.chart)
        }
        .navigationTitle("Connect")
        .scrollContentBackground(.hidden).background(color)
    }
}
