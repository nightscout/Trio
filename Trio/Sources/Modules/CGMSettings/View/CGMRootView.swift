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
                        miniHint: String(localized: "Smooth CGM readings using exponential smoothing."),
                        verboseHint: VStack(alignment: .leading, spacing: 10) {
                            Text("Default: OFF").bold()

                            Text(
                                "This feature smooths your CGM readings to reduce noise and make them easier to read. It is based on a method used in AndroidAPS (AAPS). It uses two approaches: one that reacts quickly to recent changes, and one that looks at longer trends. These are combined to give a balanced result."
                            )

                            Text(
                                "Trio will always display values based on your actual (raw) CGM readings. Smoothing does not change your real values or alerts."
                            )

                            Text("When this feature is enabled:")

                            VStack(alignment: .leading) {
                                Text(
                                    "• The main chart and treatment chart show a light gray trend line for the smoothed values. The glucose dots always show your original CGM readings."
                                )

                                Text("• In Trio history, you will see the smoothed value next to the original reading.")

                                Text("• When you long-press a chart, the pop-up will show both the original and smoothed values.")
                            }

                            Text(
                                "It can handle small gaps in data and ignores sensor error values. It needs at least 4 readings within 12 minutes to work properly. Only CGM readings are smoothed—manual entries are not changed."
                            )

                            Text(
                                "This helps Trio make more stable dosing decisions by avoiding over-reactions to small or short-term changes. Important trends are kept, while unreliable fluctuations are filtered out."
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
                        hintText: selectedVerboseHint ?? AnyView(
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
