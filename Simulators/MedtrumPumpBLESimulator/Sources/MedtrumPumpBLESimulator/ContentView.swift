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
                Text("Do not test near an active production pump")
                    .font(.title3.bold())
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
            Section("Mandatory safety isolation") {
                Label(
                    "Use a separate training iPhone and separate Trio installation.",
                    systemImage: "iphone.gen3"
                )
                Label(
                    "Keep every real Medtrum pump powered off and physically out of BLE range.",
                    systemImage: "wave.3.right.slash"
                )
                Label(
                    "Close the production pump app. This Mac app never scans for or controls pumps.",
                    systemImage: "exclamationmark.shield.fill"
                )
                Toggle(
                    "I confirm this isolated training setup contains no active real pump",
                    isOn: $model.safetyConfirmed
                )
                .fontWeight(.bold)
                .disabled(model.isAdvertising)
            }

            Section("Peripheral") {
                LabeledContent("Bluetooth", value: model.bluetoothState)
                LabeledContent("Advertising", value: model.isAdvertising ? "ON" : "OFF")
                LabeledContent("Subscribed centrals", value: "\(model.subscribers)")
                HStack {
                    Button("Start") { model.start() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isAdvertising || !model.safetyConfirmed)
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
                Text("SIMULATOR SERIAL")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(model.identity.serial)
                    .font(.system(size: 30, weight: .black, design: .monospaced))
                    .textSelection(.enabled)
                Text("Stock Trio cannot select a macOS advertisement because macOS cannot publish Medtrum manufacturer data.")
                    .font(.caption)
                    .foregroundStyle(.red)
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
