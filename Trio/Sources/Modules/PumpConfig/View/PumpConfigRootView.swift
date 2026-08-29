import SwiftUI
import Swinject

extension PumpConfig {
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
        @State var showPumpSelection: Bool = false
        @State private var pendingPump: PumpCatalogEntry?

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            NavigationView {
                Form {
                    Section(
                        header: Text("Pump Integration to Trio"),
                        content: {
                            if bluetoothManager.bluetoothAuthorization != .authorized {
                                HStack {
                                    Spacer()
                                    BluetoothRequiredView()
                                    Spacer()
                                }
                            } else if let pumpState = state.pumpState {
                                Button {
                                    state.setupPump = true
                                } label: {
                                    HStack {
                                        Image(uiImage: pumpState.image ?? UIImage())
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxWidth: 100)
                                        Text(pumpState.name)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
                                    .font(.title2)
                                }.padding()
                                Spacer()
                            } else {
                                VStack {
                                    Button {
                                        showPumpSelection.toggle()
                                    } label: {
                                        Text("Add Pump")
                                            .font(.title3) }
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .buttonStyle(.bordered)

                                    HStack(alignment: .center) {
                                        Text(
                                            "Pair your insulin pump with Trio. See hint for compatible devices."
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
                    )
                    .listRowBackground(Color.chart)
                }
                .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
                .onAppear(perform: configureView)
                .navigationTitle("Insulin Pump")
                .navigationBarTitleDisplayMode(.automatic)
                .navigationBarItems(leading: displayClose ? Button("Close", action: state.hideModal) : nil)
                .sheet(isPresented: $state.setupPump) {
                    if let pumpManager = state.provider.apsManager.pumpManager {
                        PumpSettingsView(
                            pumpManager: pumpManager,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            completionDelegate: state,
                            setupDelegate: state
                        )
                    } else if let pumpEntry = state.setupPumpEntry {
                        PumpSetupView(
                            pumpEntry: pumpEntry,
                            pumpInitialSettings: state.initialSettings,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            completionDelegate: state,
                            setupDelegate: state
                        )
                    }
                }
                .sheet(isPresented: $shouldDisplayHint) {
                    SettingInputHintView(
                        hintDetent: $hintDetent,
                        shouldDisplayHint: $shouldDisplayHint,
                        hintLabel: "Pump Pairing to Trio",
                        hintText: AnyView(
                            VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "Current Pump Models Supported:"
                                )
                                VStack(alignment: .leading) {
                                    ForEach(DeviceCatalog.pumps) { pump in
                                        Text("• \(pump.hintLine)")
                                    }
                                }
                                Text(
                                    "Note: If using a pump simulator, you will not have continuous readings from the CGM in Trio. Using a pump simulator is only advisable for becoming familiar with the app user interface. It will not give you insight on how the algorithm will respond."
                                )
                            }
                        ),
                        sheetTitle: String(localized: "Help", comment: "Help sheet title")
                    )
                }
                // Selection is applied in onDismiss so the setup sheet is presented only once the picker is gone.
                .sheet(isPresented: $showPumpSelection, onDismiss: {
                    if let entry = pendingPump {
                        pendingPump = nil
                        state.addPump(entry)
                    }
                }) {
                    DevicePickerView(
                        title: String(localized: "Add Pump", comment: "The title of the pump chooser in settings"),
                        entries: DeviceCatalog.pumps
                    ) { entry in
                        pendingPump = entry
                        showPumpSelection = false
                    }
                }
            }
        }
    }
}
