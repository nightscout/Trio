import SwiftUI

struct DeviceAlarmEditorView: View {
    @ObservedObject var store: DeviceAlertsStore
    let configID: UUID
    let isNew: Bool
    var onDone: () -> Void
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState
    @State private var working: DeviceAlertSeverityConfig

    init(
        store: DeviceAlertsStore,
        initial: DeviceAlertSeverityConfig,
        isNew: Bool,
        onDone: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.store = store
        configID = initial.id
        self.isNew = isNew
        self.onDone = onDone
        self.onCancel = onCancel
        _working = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("Behavior"),
                    footer: Text(working.severity.blurb)
                ) {
                    HStack {
                        Text(working.severity.displayName).font(.headline)
                        Spacer()
                        Text(activeLabel)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    Toggle(String(localized: "Enabled"), isOn: $working.isEnabled)
                    Toggle(
                        String(localized: "Override Silence & Focus Mode"),
                        isOn: $working.overridesSilenceAndDND
                    )
                }.listRowBackground(Color.chart)

                AlarmActiveSection(activeOption: $working.activeOption)
                AlarmAudioSection(
                    playsSound: $working.playsSound,
                    soundFilename: $working.soundFilename
                )

                Section(header: Text("Applies To")) {
                    ForEach(PumpAlertCategory.allCases.filter { $0.defaultSeverity == working.severity }) { category in
                        Text(category.displayName)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }.listRowBackground(Color.chart)

                if !isNew, store.canDelete(working) {
                    Section {
                        Button(role: .destructive) {
                            store.remove(working)
                            dismiss()
                        } label: {
                            Text("Delete Variant")
                        }
                    }.listRowBackground(Color.chart)
                }
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle(working.severity.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? String(localized: "Add") : String(localized: "Done")) {
                        if isNew {
                            store.add(working)
                        } else {
                            store.update(working)
                        }
                        onDone()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }

    private var activeLabel: String {
        switch working.activeOption {
        case .always: return String(localized: "Day & Night")
        case .day: return String(localized: "Day only")
        case .night: return String(localized: "Night only")
        }
    }
}
