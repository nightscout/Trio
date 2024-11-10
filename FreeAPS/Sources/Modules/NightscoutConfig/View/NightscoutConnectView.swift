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
        List {
            Section(
                header: Text("Connect to Nightscout"),
                content: {
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

            // TODO: Find out if this is still required or needed ?!
//            Section {
//                Toggle("Use local glucose server", isOn: $state.useLocalSource)
//                HStack {
//                    Text("Port")
//                    TextFieldWithToolBar(
//                        text: $state.localPort,
//                        placeholder: "",
//                        keyboardType: .numberPad,
//                        numberFormatter: portFormatter,
//                        allowDecimalSeparator: false
//                    )
//                }
//            } header: { Text("Local glucose source") }.listRowBackground(Color.chart)
        }
        .listSectionSpacing(sectionSpacing)
        .navigationTitle("Connect")
        .navigationBarTitleDisplayMode(.automatic)
        .scrollContentBackground(.hidden).background(color)
    }
}
