import SwiftUI

struct GlucoseAlertEditorView: View {
    @ObservedObject var store: GlucoseAlertsStore
    let alertID: UUID
    let isNew: Bool

    /// Windows the user can still pick without overlapping another alarm of
    /// the same type. The being-edited alarm is excluded from "taken" so its
    /// current option stays valid.
    private var allowedActiveOptions: [ActiveOption] {
        let available = store.availableActiveOptions(
            forType: working.type,
            excludingAlertID: isNew ? nil : alertID
        )
        return ActiveOption.allCases.filter { available.contains($0) }
    }

    let units: GlucoseUnits
    var onDone: () -> Void
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState
    @State private var working: GlucoseAlert

    init(
        store: GlucoseAlertsStore,
        initial: GlucoseAlert,
        isNew: Bool,
        units: GlucoseUnits,
        onDone: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.store = store
        alertID = initial.id
        self.isNew = isNew
        self.units = units
        self.onDone = onDone
        self.onCancel = onCancel
        _working = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                generalSection

                switch working.type {
                case .urgentLow: urgentLowBody
                case .low: lowBody
                case .fallingFast: fallingFastBody
                case .forecastedLow: forecastedLowBody
                case .high: highBody
                case .risingFast: risingFastBody
                case .carbsRequired: carbsRequiredBody
                }

                AlarmActiveSection(
                    activeOption: $working.activeOption,
                    allowed: allowedActiveOptions
                )
                AlarmAudioSection(
                    playsSound: $working.playsSound,
                    soundFilename: $working.soundFilename,
                    scope: .glucose(working.type)
                )

                if !isNew, store.canDelete(working) {
                    Section {
                        Button(role: .destructive) {
                            store.remove(working)
                            dismiss()
                        } label: {
                            Text("Delete Alarm")
                        }
                    }.listRowBackground(Color.chart)
                }
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle(working.type.displayName)
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

    // MARK: - Sections

    private var generalSection: some View {
        Section(
            header: Text("General"),
            footer: Text(working.type.blurb)
        ) {
            TextField(String(localized: "Name"), text: $working.name)
            // Urgent-low is the safety floor — the user can mute the sound
            // from the Audio section but the alarm itself is always armed.
            if working.type != .urgentLow {
                Toggle(String(localized: "Enabled"), isOn: $working.isEnabled)
            }
            Toggle(
                String(localized: "Override Silence & Focus Mode"),
                isOn: $working.overridesSilenceAndDND
            )
        }.listRowBackground(Color.chart)
    }

    private var urgentLowBody: some View {
        AlarmBGSection(
            header: String(localized: "Urgent Low Threshold"),
            footer: String(
                localized: "Recommended to always override silence and Focus mode."
            ),
            title: String(localized: "Glucose"),
            range: 54 ... 80,
            step: 1,
            units: units,
            valueMgDL: $working.thresholdMgDL
        )
    }

    private var lowBody: some View {
        AlarmBGSection(
            header: String(localized: "Low Threshold"),
            footer: String(
                localized: "Fires when glucose is at or below this value."
            ),
            title: String(localized: "Glucose"),
            range: 54 ... 100,
            step: 1,
            units: units,
            valueMgDL: $working.thresholdMgDL
        )
    }

    @ViewBuilder private var fallingFastBody: some View {
        AlarmBGSection(
            header: String(localized: "Fall Rate"),
            footer: String(
                localized: "This is the rate of drop per 5 minutes, measured over the last 15 minutes. Fires when glucose drops at least this fast."
            ),
            title: String(localized: "Drop in 5 Minutes"),
            range: GlucoseAlertType.rateRange,
            step: 1,
            units: units,
            valueMgDL: $working.thresholdMgDL
        )
        AlarmBGSection(
            header: String(localized: "Only When Below"),
            footer: String(localized: "Fires only when glucose is at or below this value."),
            title: String(localized: "Glucose"),
            range: GlucoseAlertType.glucoseLimitRange,
            step: 1,
            units: units,
            valueMgDL: glucoseLimitBinding
        )
    }

    @ViewBuilder private var risingFastBody: some View {
        AlarmBGSection(
            header: String(localized: "Rise Rate"),
            footer: String(
                localized: "This is the rate of rise per 5 minutes, measured over the last 15 minutes. Fires when glucose rises at least this fast."
            ),
            title: String(localized: "Rise in 5 Minutes"),
            range: GlucoseAlertType.rateRange,
            step: 1,
            units: units,
            valueMgDL: $working.thresholdMgDL
        )
        AlarmBGSection(
            header: String(localized: "Only When Above"),
            footer: String(localized: "Fires only when glucose is at or above this value."),
            title: String(localized: "Glucose"),
            range: GlucoseAlertType.glucoseLimitRange,
            step: 1,
            units: units,
            valueMgDL: glucoseLimitBinding
        )
    }

    private var glucoseLimitBinding: Binding<Decimal> {
        Binding(
            get: { working.glucoseLimitMgDL ?? working.type.defaultGlucoseLimitMgDL ?? 0 },
            set: { working.glucoseLimitMgDL = $0 }
        )
    }

    private var forecastedLowBody: some View {
        AlarmBGSection(
            header: String(localized: "Low Threshold"),
            footer: String(
                localized: "Fires when the forecast at +20 minutes (blended across all available prediction curves) is at or below this value."
            ),
            title: String(localized: "Glucose"),
            range: 54 ... 100,
            step: 1,
            units: units,
            valueMgDL: $working.thresholdMgDL
        )
    }

    private var highBody: some View {
        AlarmBGSection(
            header: String(localized: "High Threshold"),
            footer: String(
                localized: "Fires when glucose is at or above this value."
            ),
            title: String(localized: "Glucose"),
            range: 100 ... 400,
            step: 1,
            units: units,
            valueMgDL: $working.thresholdMgDL
        )
    }

    private var carbsRequiredBody: some View {
        AlarmGramsSection(
            header: String(localized: "Carbs Required Threshold"),
            footer: String(
                localized: "Fires when the algorithm suggests to eat at least this many grams of carbs to avoid a low."
            ),
            title: String(localized: "Carbs"),
            range: 5 ... 50,
            step: 1,
            valueGrams: $working.thresholdMgDL
        )
    }
}
