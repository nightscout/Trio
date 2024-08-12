import LoopKitUI
import SwiftUI
import Swinject

extension CGM {
    struct RootView: BaseView {
        let resolver: Resolver
        let displayClose: Bool
        @StateObject var state = StateModel()
        @State private var setupCGM = false

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: String?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

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

        var body: some View {
            NavigationView {
                Form {
                    Section(
                        header: Text("CGM Integration to Trio"),
                        content: {
                            VStack {
                                Picker("Type", selection: $state.cgmCurrent) {
                                    ForEach(state.listOfCGM) { type in
                                        VStack(alignment: .leading) {
                                            Text(type.displayName)
                                            Text(type.subtitle).font(.caption).foregroundColor(.secondary)
                                        }.tag(type)
                                    }
                                }.padding(.top)

                                HStack(alignment: .top) {
                                    Text(
                                        "Lorem ipsum dolor sit amet, consetetur sadipscing elitr."
                                    )
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    Spacer()
                                    Button(
                                        action: {
                                            hintLabel = "Available CGM Types for Trio"
                                            selectedVerboseHint =
                                                "CGM Types… bla bla \n\nLorem ipsum dolor sit amet, consetetur sadipscing elitr."
                                            shouldDisplayHint.toggle()
                                        },
                                        label: {
                                            HStack {
                                                Image(systemName: "questionmark.circle")
                                            }
                                        }
                                    ).buttonStyle(BorderlessButtonStyle())
                                }.padding(.top)
                            }.padding(.bottom)

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

                            if state.cgmCurrent.type == .plugin {
                                Button {
                                    setupCGM.toggle()
                                } label: {
                                    HStack {
                                        Text("CGM Configuration")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    ).listRowBackground(Color.chart)

                    if let appURL = state.urlOfApp() {
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
                                Label(state.displayNameOfApp() ?? "-", systemImage: "waveform.path.ecg.rectangle").font(.title3)
                                    .padding() }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .buttonStyle(.bordered)
                        }
                        .listRowBackground(Color.clear)
                    } else if state.cgmCurrent.type == .nightscout {
                        if let url = state.url {
                            Section {
                                Button {
                                    UIApplication.shared.open(url, options: [:]) { success in
                                        if !success {
                                            self.router.alertMessage
                                                .send(MessageContent(content: "No URL available", type: .warning))
                                        }
                                    }
                                }
                                label: { Label("Open URL", systemImage: "waveform.path.ecg.rectangle").font(.title3).padding() }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .buttonStyle(.bordered)
                            }
                            .listRowBackground(Color.clear)
                        } else {
                            Section {
                                Button {
                                    state.showModal(for: .nighscoutConfigDirect)
                                }
                                label: {
                                    Label("Config Nightscout", systemImage: "waveform.path.ecg.rectangle").font(.title3).padding()
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .buttonStyle(.bordered)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }

                    if state.cgmCurrent.type == .xdrip {
                        Section(header: Text("Heartbeat")) {
                            VStack(alignment: .leading) {
                                if let cgmTransmitterDeviceAddress = state.cgmTransmitterDeviceAddress {
                                    Text("CGM address :").padding(.top)
                                    Text(cgmTransmitterDeviceAddress)
                                } else {
                                    Text("CGM is not used as heartbeat.").padding(.top)
                                }

                                HStack(alignment: .top) {
                                    Text(
                                        "Lorem ipsum dolor sit amet, consetetur sadipscing elitr."
                                    )
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    Spacer()
                                    Button(
                                        action: {
                                            hintLabel = "CGM Heartbeat"
                                            selectedVerboseHint = "Lorem ipsum dolor sit amet, consetetur sadipscing elitr."
                                            shouldDisplayHint.toggle()
                                        },
                                        label: {
                                            HStack {
                                                Image(systemName: "questionmark.circle")
                                            }
                                        }
                                    ).buttonStyle(BorderlessButtonStyle())
                                }.padding(.vertical)
                            }
                        }.listRowBackground(Color.chart)
                    }

                    if state.cgmCurrent.type == .plugin && state.cgmCurrent.id.contains("Libre") {
                        Section {
                            Text("Libre Calibrations").navigationLink(to: .calibrations, from: self)
                        }.listRowBackground(Color.chart)
                    }

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.smoothGlucose,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = "Smooth Glucose Value"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Smooth Glucose Value",
                        miniHint: "Smooth CGM readings using Savitzky–Golay filtering.",
                        verboseHint: "Smooth Glucose Value… bla bla bla"
                    )
                }
                .scrollContentBackground(.hidden).background(color)
                .onAppear(perform: configureView)
                .navigationTitle("CGM")
                .navigationBarTitleDisplayMode(.automatic)
                .sheet(isPresented: $shouldDisplayHint) {
                    SettingInputHintView(
                        hintDetent: $hintDetent,
                        shouldDisplayHint: $shouldDisplayHint,
                        hintLabel: hintLabel ?? "",
                        hintText: selectedVerboseHint ?? "",
                        sheetTitle: "Help"
                    )
                }
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
                .screenNavigation(self)
            }
        }
    }
}
