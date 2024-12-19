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
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            NavigationView {
                List {
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

                                HStack(alignment: .center) {
                                    Text(
                                        "Select your CGM."
                                    )
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    Spacer()
                                    Button(
                                        action: {
                                            hintLabel = "Available CGM Types for Trio"
                                            selectedVerboseHint =
                                                AnyView(
                                                    Text(
                                                        "• Dexcom G5 \n• Dexcom G6 / ONE \n• Dexcom G7 / ONE+ \n• Dexcom Share \n• Freestyle Libre \n• Freestyle Libre Demo \n• Glucose Simulator \n• Medtronic Enlite \n• Nightscout \n• xDrip4iOS"
                                                    )
                                                )
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

                                HStack(alignment: .center) {
                                    Text(
                                        "A heartbeat tells Trio to start a loop cycle. \nThis is required to keep looping."
                                    )
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    Spacer()
                                    Button(
                                        action: {
                                            hintLabel = "CGM Heartbeat"
                                            selectedVerboseHint =
                                                AnyView(
                                                    Text(
                                                        "The CGM Heartbeat can come from either a CGM or a pump to wake up Trio when phone is locked or in the background. If CGM is on the same phone as Trio and xDrip4iOS is configured to use the same AppGroup as Trio and the heartbeat feature is turned on in xDrip4iOS, then the CGM can provide a heartbeat to wake up Trio when phone is locked or app is in the background."
                                                    )
                                                )
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
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = "Smooth Glucose Value"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Smooth Glucose Value",
                        miniHint: "Smooth CGM readings using Savitzky-Golay filtering.",
                        verboseHint:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Default: OFF").bold()
                            Text(
                                "This filter looks at small groups of nearby readings and fits them to a simple mathematical curve. This process doesn't change the overall pattern of your glucose data but helps smooth out the \"noise\" or irregular fluctuations that could lead to false highs or lows."
                            )
                            Text(
                                "Because your glucose readings are taken at regular intervals, the filter can use a set of pre-calculated \"weights\" to adjust each group of readings, making the calculations fast and efficient. It's designed to keep the important trends in your data while minimizing those small, misleading variations, giving you and Trio a clearer sense of where your blood sugar is really headed."
                            )
                            Text(
                                "This type of filtering is useful in Trio, as it can help prevent over-corrections based on inaccurate glucose readings. This can help reduce the impact of sudden spikes or dips that might not reflect your true blood glucose levels."
                            )
                        }
                    )
                }
                .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
                .onAppear(perform: configureView)
                .navigationTitle("CGM")
                .navigationBarTitleDisplayMode(.automatic)
                .navigationBarItems(leading: displayClose ? Button("Close", action: state.hideModal) : nil)
                .sheet(isPresented: $shouldDisplayHint) {
                    SettingInputHintView(
                        hintDetent: $hintDetent,
                        shouldDisplayHint: $shouldDisplayHint,
                        hintLabel: hintLabel ?? "",
                        hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                        sheetTitle: "Help"
                    )
                }
                .onChange(of: setupCGM) { _, setupCGM in
                    state.setupCGM = setupCGM
                }
                .onChange(of: state.setupCGM) { _, setupCGM in
                    self.setupCGM = setupCGM
                }
                .screenNavigation(self)
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
        }
    }
}
