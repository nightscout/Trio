import LoopKitUI
import SwiftUI
import Swinject

struct OtherCGMView: BaseView {
    let resolver: Resolver
    @ObservedObject var state: CGM.StateModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section(
                    header: Text("Configuration"),
                    content: {
                        if state.cgmCurrent.type == .nightscout {
                            NavigationLink(
                                destination: NightscoutConfig.RootView(resolver: resolver, displayClose: false),
                                label: { Text("Config Nightscout") }
                            )
                        } else if state.cgmCurrent.type == .xdrip {
                            VStack(alignment: .leading) {
                                if let cgmTransmitterDeviceAddress = state.cgmTransmitterDeviceAddress {
                                    Text("CGM address :").padding(.top)
                                    Text(cgmTransmitterDeviceAddress)
                                } else {
                                    Text("CGM is not used as heartbeat.").padding(.top)
                                }

                                HStack(alignment: .center) {
                                    Text(
                                        "A heartbeat tells Trio to start a loop cycle. This is required for closed loop."
                                    )
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    Spacer()
                                }.padding(.vertical)
                            }
                        }

                        if let link = state.cgmCurrent.type.externalLink {
                            Button {
                                UIApplication.shared.open(link, options: [:], completionHandler: nil)
                            } label: {
                                HStack {
                                    Text("About this source")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let appURL = state.urlOfApp() {
                            Button {
                                UIApplication.shared.open(appURL, options: [:]) { success in
                                    if !success {
                                        self.router.alertMessage
                                            .send(MessageContent(content: "Unable to open the app", type: .warning))
                                    }
                                }
                            }
                            label: {
                                HStack {
                                    Text(state.displayNameOfApp() ?? "-")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                ).listRowBackground(Color.chart)

                Button {
                    state.deleteCGM()
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Text("Delete CGM")
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: 35)
                }
                .listRowBackground(Color(.systemRed))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .navigationTitle(state.cgmCurrent.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                /// proper positioning should be .leading
                /// but to keep this in line with LoopKit submodules, set placement to .trailing
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
        }
    }
}
