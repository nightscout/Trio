import SwiftUI

struct DeviceAlarmEditorView: View {
    let severity: DeviceAlertSeverity
    @ObservedObject var store: DeviceAlertsStore

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState
    @State private var working: DeviceAlertSeverityConfig

    init(severity: DeviceAlertSeverity, store: DeviceAlertsStore) {
        self.severity = severity
        self.store = store
        _working = State(initialValue: store.config(for: severity) ?? DeviceAlertSeverityConfig(severity: severity))
    }

    var body: some View {
        Form {
            Section(header: Text("Behavior"), footer: Text(severity.blurb)) {
                Text(severity.displayName).font(.headline)
                Toggle(
                    String(localized: "Override Silence & Focus Mode"),
                    isOn: $working.overridesSilenceAndDND
                )
            }
            .listRowBackground(Color.chart)

            AlarmAudioSection(
                playsSound: $working.playsSound,
                soundFilename: $working.soundFilename
            )

            Section(header: Text("Applies To")) {
                ForEach(PumpAlertCategory.allCases.filter { $0.defaultSeverity == severity }) { category in
                    Text(category.displayName)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }.listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle(severity.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: working) { _, new in store.update(new) }
    }
}
