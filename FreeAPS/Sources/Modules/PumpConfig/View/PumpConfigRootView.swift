import SwiftUI
import Swinject

extension PumpConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        let displayClose: Bool
        @StateObject var state = StateModel()

        var body: some View {
            NavigationView {
                Form {
                    Section(header: Text("Model")) {
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
                            Button("Add Medtronic") { state.addPump(.minimed) }
                            Button("Add Omnipod") { state.addPump(.omnipod) }
                            Button("Add Omnipod Dash") { state.addPump(.omnipodBLE) }
                            Button("Add Simulator") { state.addPump(.simulator) }
                        }
                    }
                }
                .onAppear(perform: configureView)
                .navigationTitle("Pump config")
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
            }
        }
    }
}
