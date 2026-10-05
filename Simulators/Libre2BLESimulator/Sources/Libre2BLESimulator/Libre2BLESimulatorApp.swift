import Libre2Protocol
import SwiftUI

@main
struct Libre2BLESimulatorApp: App {
    @StateObject private var model = SimulatorModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 820, minHeight: 700)
        }
        .windowStyle(.titleBar)
    }
}

private struct ContentView: View {
    @ObservedObject var model: SimulatorModel

    var body: some View {
        VStack(spacing: 0) {
            Text("TRAINING SIMULATOR — NOT A MEDICAL DEVICE")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(.red)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusPanel
                    Divider()
                    sensorPanel
                    Divider()
                    scenarioPanel
                    Divider()
                    connectionPanel
                }
                .padding(20)
            }
        }
    }

    private var statusPanel: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Libre 2 BLE Peripheral").font(.title.bold())
                Text("Bluetooth: \(model.bluetoothState)")
                Text(model.isAdvertising ? "Advertising FDE3" : "Not advertising")
                    .foregroundStyle(model.isAdvertising ? .green : .secondary)
            }
            Spacer()
            Button(model.wantsAdvertising ? "Stop Advertising" : "Start Advertising") {
                model.wantsAdvertising ? model.stop() : model.start()
            }
            .buttonStyle(.borderedProminent)
            Button("Reset", role: .destructive) { model.reset() }
        }
    }

    private var sensorPanel: some View {
        GroupBox("Synthetic Sensor Identity") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow { Text("Advertised name"); Text(model.localName).textSelection(.enabled) }
                GridRow { Text("Serial"); Text(model.serial).textSelection(.enabled) }
                GridRow { Text("UID"); Text(model.sensorUIDHex).monospaced().textSelection(.enabled) }
                GridRow {
                    Text("Age")
                    Stepper("\(model.sensorAgeMinutes) minutes", value: $model.sensorAgeMinutes, in: 0...65_535)
                }
                GridRow {
                    Text("State")
                    Text(model.sensorAgeMinutes < 60 ? "Warmup" :
                         model.sensorAgeMinutes >= Libre2Profile.maximumAgeMinutes ? "Expired" : "Ready")
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var scenarioPanel: some View {
        GroupBox("Training Scenario") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Glucose target")
                    HStack {
                        Slider(value: $model.glucose, in: 40...350, step: 1)
                        Text("\(Int(model.glucose)) mg/dL").frame(width: 92, alignment: .trailing)
                    }
                }
                GridRow {
                    Text("Trend")
                    Picker("Trend", selection: $model.trend) {
                        ForEach(Libre2Trend.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                GridRow {
                    Text("Automatic curve")
                    HStack {
                        Toggle("Sinusoidal curve", isOn: $model.automaticCurve)
                        Slider(value: $model.curveAmplitude, in: 5...100, step: 5)
                        Text("±\(Int(model.curveAmplitude))").frame(width: 50)
                    }
                }
                GridRow {
                    Text("Alarm scenario")
                    Picker("Alarm", selection: $model.alarmScenario) {
                        ForEach(AlarmScenario.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Dropouts")
                    Stepper(
                        model.dropoutEvery == 0 ? "Disabled" : "Every \(model.dropoutEvery) packets",
                        value: $model.dropoutEvery,
                        in: 0...20
                    )
                }
                GridRow {
                    Text("Packet interval")
                    HStack {
                        Slider(value: $model.intervalSeconds, in: 5...300, step: 5) {
                            Text("Interval")
                        } onEditingChanged: { editing in
                            if !editing { model.restartTimer() }
                        }
                        Text("\(Int(model.intervalSeconds)) s").frame(width: 55)
                    }
                }
                GridRow {
                    Text("")
                    Button("Send Packet Now") { model.sendNow() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var connectionPanel: some View {
        GroupBox("Connection and Protocol Log") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("\(model.subscriberCount) subscribed central(s)", systemImage: "iphone")
                    Spacer()
                    Text(model.isUnlocked ? "Session unlocked" : "Waiting for F001 unlock")
                        .foregroundStyle(model.isUnlocked ? .green : .orange)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(model.logs.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 180)
                .padding(8)
                .background(.black.opacity(0.85))
                .foregroundStyle(.green)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.vertical, 6)
        }
    }
}
