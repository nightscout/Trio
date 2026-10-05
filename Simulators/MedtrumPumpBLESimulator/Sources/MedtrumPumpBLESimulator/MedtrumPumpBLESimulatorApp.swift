import SwiftUI

@main
struct MedtrumPumpBLESimulatorApp: App {
    @StateObject private var model = SimulatorModel()

    var body: some Scene {
        WindowGroup("Medtrum Pump Simulator") {
            ContentView(model: model)
                .frame(minWidth: 850, minHeight: 680)
        }
        .windowResizability(.contentMinSize)
    }
}
