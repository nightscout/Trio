import LoopKitUI
import SwiftUI
import Swinject

extension CGM {
    struct RootView: BaseView {
        let resolver: Resolver
        let displayClose: Bool
        @StateObject var state = StateModel()
        @State private var setupCGM = false

        // @AppStorage(UserDefaults.BTKey.cgmTransmitterDeviceAddress.rawValue) private var cgmTransmitterDeviceAddress: String? = nil

        var body: some View {
            NavigationView {
                Form {
                    Section(header: Text("CGM")) {
                        Picker("Type", selection: $state.cgmCurrent) {
                            ForEach(state.listOfCGM) { type in
                                VStack(alignment: .leading) {
                                    Text(type.displayName)
                                    Text(type.subtitle).font(.caption).foregroundColor(.secondary)
                                }.tag(type)
                            }
                        }
                        if let link = state.cgmCurrent.type.externalLink {
                            Button("About this source") {
                                UIApplication.shared.open(link, options: [:], completionHandler: nil)
                            }
                        }
                    }

                    if let cgmFetchManager = state.cgmManager {
                        if let appURL = state.urlOfApp()
                        {
                            Section {
                                Button {
                                    UIApplication.shared.open(appURL, options: [:]) { success in
                                        if !success {
                                            self.router.alertMessage
                                                .send(MessageContent(content: "Unable to open the app", type: .warning))
                                        }
                                    }
                                }

                                label: {
                                    Label(state.displayNameOfApp(), systemImage: "waveform.path.ecg.rectangle").font(.title3) }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .buttonStyle(.bordered)
                            }
                            .listRowBackground(Color.clear)
                        } else if state.cgmCurrent.type == .nightscout && state.url != nil {
                            Section {
                                Button {
                                    UIApplication.shared.open(state.url!, options: [:]) { success in
                                        if !success {
                                            self.router.alertMessage
                                                .send(MessageContent(content: "No URL available", type: .warning))
                                        }
                                    }
                                }
                                label: { Label("Open URL", systemImage: "waveform.path.ecg.rectangle").font(.title3) }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .buttonStyle(.bordered)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }

                    if state.cgmCurrent.type == .plugin {
                        Section {
                            Button("CGM Configuration") {
                                setupCGM.toggle()
                            }
                        }
                    }
                    if state.cgmCurrent.type == .xdrip {
                        Section(header: Text("Heartbeat")) {
                            VStack(alignment: .leading) {
                                if let cgmTransmitterDeviceAddress = state.cgmTransmitterDeviceAddress {
                                    Text("CGM address :")
                                    Text(cgmTransmitterDeviceAddress)
                                } else {
                                    Text("CGM is not used as heartbeat.")
                                }
                            }
                        }
                    }
                    if state.cgmCurrent.type == .plugin && state.cgmCurrent.id.contains("Libre") {
                        Section(header: Text("Calibrations")) {
                            Text("Calibrations").navigationLink(to: .calibrations, from: self)
                        }
                    }

                    // }

                    Section(header: Text("Calendar")) {
                        Toggle("Create events in calendar", isOn: $state.createCalendarEvents)
                        if state.calendarIDs.isNotEmpty {
                            Picker("Calendar", selection: $state.currentCalendarID) {
                                ForEach(state.calendarIDs, id: \.self) {
                                    Text($0).tag($0)
                                }
                            }
                        }
                    }

                    Section(header: Text("Experimental")) {
                        Toggle("Smooth Glucose Value", isOn: $state.smoothGlucose)
                    }
                }

                .onAppear(perform: configureView)
                .navigationTitle("CGM")
                .navigationBarTitleDisplayMode(.automatic)
                .navigationBarItems(leading: displayClose ? Button("Close", action: state.hideModal) : nil)
                .sheet(isPresented: $setupCGM) {
                    if let cgmFetchManager = state.cgmManager,
                       let cgmManager = cgmFetchManager.cgmManager,
                       state.cgmCurrent.type == cgmFetchManager.cgmGlucoseSourceType,
                       state.cgmCurrent.id == cgmFetchManager.cgmGlucosePluginId
                    {
                        CGMSettingsView(
                            cgmManager: cgmManager,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            unit: state.settingsManager.settings.units,
                            completionDelegate: state
                        )
                    } else {
                        CGMSetupView(
                            CGMType: state.cgmCurrent,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            unit: state.settingsManager.settings.units,
                            completionDelegate: state,
                            setupDelegate: state,
                            pluginCGMManager: self.state.pluginCGMManager
                        )
                    }
                }
                .onChange(of: setupCGM) { setupCGM in
                    state.setupCGM = setupCGM
                }
                .onChange(of: state.setupCGM) { setupCGM in
                    self.setupCGM = setupCGM
                }
            }
        }
    }
}
