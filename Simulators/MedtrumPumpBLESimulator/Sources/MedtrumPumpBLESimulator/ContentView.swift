import MedtrumSimulatorProtocol
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: SimulatorModel

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("TRAINING SIMULATOR")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.white)
                Text("Medtrum Pump Simulator — NEVER A REAL PUMP")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.red.gradient, in: RoundedRectangle(cornerRadius: 12))

            HStack(alignment: .top, spacing: 18) {
                controls
                    .frame(width: 370)
                eventLog
            }
        }
        .padding(20)
    }

    private var controls: some View {
        Form {
            Section("Peripheral") {
                LabeledContent("Bluetooth", value: model.bluetoothState)
                LabeledContent("Advertising", value: model.isAdvertising ? "ON" : "OFF")
                LabeledContent("Subscribed centrals", value: "\(model.subscribers)")
                HStack {
                    Button("Start") { model.start() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isAdvertising)
                    Button("Stop") { model.stop() }
                        .disabled(!model.isAdvertising)
                    Button("Reset") { model.reset() }
                }
            }

            Section("Simulator identity") {
                Picker("Device", selection: $model.identity) {
                    ForEach(SimulatorModel.Identity.allCases) { identity in
                        Text(identity.rawValue).tag(identity)
                    }
                }
                .onChange(of: model.identity) { model.identityChanged() }
                LabeledContent("Serial to enter in Trio", value: model.identity.serial)
                LabeledContent("BLE local name", value: "MT-SIM")
            }

            Section("Pump state") {
                LabeledContent("Patch", value: model.patchState)
                LabeledContent("Bolus", value: model.bolusDescription)
                HStack {
                    Text("Reservoir")
                    Slider(value: $model.reservoir, in: 0 ... model.identity.reservoirCapacity, step: 0.05)
                    Text(model.reservoir.formatted(.number.precision(.fractionLength(1)))) + Text(" U")
                }
                HStack {
                    Text("Battery")
                    Slider(value: $model.battery, in: 1.8 ... 3.2, step: 0.01)
                    Text(model.battery.formatted(.number.precision(.fractionLength(2)))) + Text(" V")
                }
                HStack {
                    Text("Basal")
                    Slider(value: $model.basalRate, in: 0 ... 10, step: 0.05)
                    Text(model.basalRate.formatted(.number.precision(.fractionLength(2)))) + Text(" U/h")
                }
                Button("Apply Pump Values") { model.controlsChanged() }
            }

            Section("Training fault injection") {
                Picker("Condition", selection: $model.selectedAlarm) {
                    ForEach(AlarmInjection.allCases) { alarm in
                        Text(alarm.rawValue).tag(alarm)
                    }
                }
                Button("Inject Selected Condition") { model.injectAlarm() }
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }

    private var eventLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Protocol Event Log")
                .font(.headline)
            List(model.logEntries, id: \.self) { entry in
                Text(entry)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .overlay {
                if model.logEntries.isEmpty {
                    ContentUnavailableView("No events", systemImage: "wave.3.right")
                }
            }
        }
    }
}
