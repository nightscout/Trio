import SwiftUI
import Swinject

extension PumpConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        let displayClose: Bool
        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State var showPumpSelection: Bool = false

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
                        header: Text("Pump Integration to Trio"),
                        content: {
                            if let pumpState = state.pumpState {
                                Button {
                                    state.setupPump = true
                                } label: {
                                    HStack {
                                        Image(uiImage: pumpState.image ?? UIImage()).padding()
                                        Text(pumpState.name)
                                    }
                                }
                                if state.alertNotAck {
                                    Spacer()
                                    Button("Acknowledge all alerts") { state.ack() }
                                }
                            } else {
                                VStack {
                                    Button {
                                        showPumpSelection.toggle()
                                    } label: {
                                        Text("Add Pump")
                                            .font(.title3) }
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .buttonStyle(.bordered)

                                    HStack(alignment: .top) {
                                        Text(
                                            "Pair a compatible pump with Trio. See details for available devices."
                                        )
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                        .lineLimit(nil)
                                        Spacer()
                                        Button(
                                            action: {
                                                hintLabel = "Pump Pairing to Trio"
                                                selectedVerboseHint =
                                                    AnyView(
                                                        Text(
                                                            "Current Pump Models Supported:\n\n•Medtronic\n•Omnipod Eros\n•Omnipod Dash\n•Pump Simulator\n\nNote: If using a pump simulator, you will not have continuous readings from the CGM in Trio. Using a pump simulator is only advisable for becoming familiar with the app user interface. It will not give you insight on how the algorithm will respond."
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
                                }.padding(.vertical)
                            }
                        }
                    )
                    .padding(.top)
                    .listRowBackground(Color.chart)
                }
                .scrollContentBackground(.hidden).background(color)
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
                    } else {
                        PumpSetupView(
                            pumpType: state.setupPumpType,
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
                        hintLabel: hintLabel ?? "",
                        hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                        sheetTitle: "Help"
                    )
                }
                .confirmationDialog("Pump Model", isPresented: $showPumpSelection) {
                    Button("Medtronic") { state.addPump(.minimed) }
                    Button("Omnipod Eros") { state.addPump(.omnipod) }
                    Button("Omnipod Dash") { state.addPump(.omnipodBLE) }
                    Button("Pump Simulator") { state.addPump(.simulator) }
                } message: { Text("Select Pump Model") }
            }
        }
    }
}
