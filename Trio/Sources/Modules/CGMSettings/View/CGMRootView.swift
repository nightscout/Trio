import LoopKitUI
import SwiftUI
import Swinject

extension CGMSettings {
    struct RootView: BaseView {
        let resolver: Resolver
        let displayClose: Bool
        let bluetoothManager: BluetoothStateManager
        @StateObject var state = StateModel()
        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State var showCGMSelection: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var cgmSelectionButtons: some View {
            ForEach(cgmOptions, id: \.name) { option in
                if let cgm = state.listOfCGM.first(where: option.predicate) {
                    Button(option.name) {
                        state.addCGM(cgm: cgm)
                    }
                }
            }
        }

        var body: some View {
            NavigationView {
                Form {
                    Section(
                        header: Text("CGM Integration to Trio"),
                        content: {
                            if bluetoothManager.bluetoothAuthorization != .authorized {
                                HStack {
                                    Spacer()
                                    BluetoothRequiredView()
                                    Spacer()
                                }
                            } else {
                                let cgmState = state.cgmCurrent
                                if cgmState.type != .none {
                                    Button {
                                        state.shouldDisplayCGMSetupSheet = true
                                    } label: {
                                        HStack {
                                            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                                            Text(cgmState.displayName)
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
                                        .font(.title2)
                                    }.padding()
                                } else {
                                    VStack {
                                        Button {
                                            showCGMSelection.toggle()
                                        } label: {
                                            Text("Add CGM")
                                                .font(.title3) }
                                            .frame(maxWidth: .infinity, alignment: .center)
                                            .buttonStyle(.bordered)

                                        HStack(alignment: .center) {
                                            Text(
                                                "Pair your CGM with Trio. See hint for compatible devices."
                                            )
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                            .lineLimit(nil)
                                            Spacer()
                                            Button(
                                                action: {
                                                    shouldDisplayHint.toggle()
                                                },
                                                label: {
                                                    HStack {
                                                        Image(systemName: "questionmark.circle")
                                                    }
                                                }
                                            ).buttonStyle(BorderlessButtonStyle())
                                        }.padding(.top)
                                    }.padding(.vertical)
                                }
                            }
                        }
                    )
                    .listRowBackground(Color.chart)

                    if state.cgmCurrent.type == .plugin && state.cgmCurrent.id.contains("Libre") {
                        Section {
                            NavigationLink(
                                destination: Calibrations.RootView(resolver: resolver),
                                label: { Text("Libre Calibrations") }
                            )
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
                                hintLabel = String(localized: "Smooth Glucose Value")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: String(localized: "Smooth Glucose Value"),
                        miniHint: String(localized: "Smooth CGM readings using Savitzky-Golay filtering."),
                        verboseHint: VStack(alignment: .leading, spacing: 10) {
                            Text("Default: OFF").bold()
                            Text(
                                "This filter looks at small groups of nearby readings and fits them to a simple mathematical curve. This process doesn't change the overall pattern of your glucose data but helps smooth out the \"noise\" or irregular fluctuations that could lead to false highs or lows."
                            )
                            Text(
                                "It's designed to keep the important trends in your data while minimizing those small, misleading variations, giving you and Trio a clearer sense of where your blood sugar is really headed. This type of filtering is useful in Trio, as it can help prevent over-corrections based on inaccurate glucose readings. This can help reduce the impact of sudden spikes or dips that might not reflect your true blood glucose levels."
                            )
                            Text(
                                "Note: If enabled, the smoothed values you see in Trio may differ from what is shown in your CGM app."
                            )
                        }
                    )
                }
                .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
                .onAppear(perform: configureView)
                .navigationTitle("CGM")
                .navigationBarTitleDisplayMode(.automatic)
                .navigationBarItems(leading: displayClose ? Button("Close", action: state.hideModal) : nil)
                .sheet(isPresented: $state.shouldDisplayCGMSetupSheet) {
                    switch state.cgmCurrent.type {
                    case .enlite,
                         .nightscout,
                         .none,
                         .simulator,
                         .xdrip:

                        CustomCGMOptionsView(
                            resolver: self.resolver,
                            state: state,
                            cgmCurrent: state.cgmCurrent,
                            deleteCGM: state.deleteCGM
                        )

                    case .plugin:
                        if let fetchGlucoseManager = state.fetchGlucoseManager,
                           let cgmManager = fetchGlucoseManager.cgmManager,
                           state.cgmCurrent.type == fetchGlucoseManager.cgmGlucoseSourceType,
                           state.cgmCurrent.id == fetchGlucoseManager.cgmGlucosePluginId
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
                            ).onDisappear {
                                if state.fetchGlucoseManager.cgmGlucoseSourceType == .none {
                                    state.cgmCurrent = cgmDefaultModel
                                }
                            }
                        }
                    }
                }
                .sheet(isPresented: $shouldDisplayHint) {
                    SettingInputHintView(
                        hintDetent: $hintDetent,
                        shouldDisplayHint: $shouldDisplayHint,
                        hintLabel: hintLabel ?? "",
                        hintText: AnyView(
                            VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "Current CGM Models Supported:"
                                )
                                VStack(alignment: .leading) {
                                    Text("• Dexcom G5")
                                    Text("• Dexcom G6 / ONE")
                                    Text("• Dexcom G7 / ONE+")
                                    Text("• Dexcom Share")
                                    Text("• Freestyle Libre")
                                    Text("• Freestyle Libre Demo")
                                    Text("• Glucose Simulator")
                                    Text("• Medtronic Enlite")
                                    Text("• Nightscout")
                                    Text("• xDrip4iOS")
                                }
                                Text(
                                    "Note: The CGM Heartbeat can come from either a CGM or a pump to wake up Trio when phone is locked or in the background. If CGM is on the same phone as Trio and xDrip4iOS is configured to use the same AppGroup as Trio and the heartbeat feature is turned on in xDrip4iOS, then the CGM can provide a heartbeat to wake up Trio when phone is locked or app is in the background."
                                )
                            }
                        ),
                        sheetTitle: String(localized: "Help", comment: "Help sheet title")
                    )
                }
                .confirmationDialog("CGM Model", isPresented: $showCGMSelection) {
                    cgmSelectionButtons
                } message: {
                    Text("Select CGM Model")
                }
            }
        }
    }
}
