import LoopKit
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
                    // Critical-tier configs are always armed — the user can
                    // mute the sound via the Audio section but not turn the
                    // alarm itself off. Other tiers expose the toggle.
                    if working.severity != .critical {
                        Toggle(String(localized: "Enabled"), isOn: $working.isEnabled)
                    }
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
                    ForEach(conceptsForTier(working.severity), id: \.self) { concept in
                        Text(concept.displayTitle)
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

    /// Distinct alarm concepts whose catalog entries fall into this tier.
    /// Sorted by display title so the list is stable across plugin changes.
    private func conceptsForTier(_ tier: DeviceAlertSeverity) -> [LoopKit.Alert.CatalogConcept] {
        var seen: Set<LoopKit.Alert.CatalogConcept> = []
        var ordered: [LoopKit.Alert.CatalogConcept] = []
        for entry in AlertCatalogRegistry.entries
            where DeviceAlertSeverity(level: entry.interruptionLevel) == tier
        {
            if seen.insert(entry.concept).inserted {
                ordered.append(entry.concept)
            }
        }
        return ordered.sorted { $0.displayTitle < $1.displayTitle }
    }
}
