import LoopKitUI
import SwiftUI
import Swinject

extension CGM {
    struct OtherCGMView: BaseView {
        let resolver: Resolver
        @ObservedObject var state: CGM.StateModel
        let cgmCurrent: CGMModel
        let deleteCGM: () -> Void

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        @Environment(\.presentationMode) var presentationMode

        var body: some View {
            NavigationView {
                Form {
                    if cgmCurrent.type != .none {
                        Section(
                            header: Text("Configuration"),
                            content: {
                                if cgmCurrent.type == .nightscout {
                                    NavigationLink(
                                        destination: NightscoutConfig.RootView(resolver: resolver, displayClose: false),
                                        label: { Text("Config Nightscout") }
                                    )
                                } else if cgmCurrent.type == .xdrip {
                                    VStack(alignment: .leading) {
                                        if let cgmTransmitterDeviceAddress = UserDefaults.standard.cgmTransmitterDeviceAddress {
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
                                } else if cgmCurrent.type == .simulator {
                                    Text(
                                        "Trio's glucose simulator does not offer any configuration. Its use is strictly for demonstration purposes only."
                                    )
                                }

                                if let link = cgmCurrent.type.externalLink {
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

                                if let appURL = cgmCurrent.type.appURL {
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
                                            Text(cgmCurrent.displayName)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        ).listRowBackground(Color.chart)
                    }

                    Button {
                        deleteCGM()
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
                .navigationTitle(cgmCurrent.displayName)
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
}
