import Foundation

extension TherapySettingsEditor.StateModel {
    func getInsulinSensitivityValueOptions(unit: TherapySettingsEditor.Unit) -> [Decimal] {
        let settingsProvider = PickerSettingsProvider.shared
        let sensitivityPickerSetting = PickerSetting(value: 100, step: 1, min: 9, max: 540, type: .glucose)
        return settingsProvider.generatePickerValues(from: sensitivityPickerSetting, units: unit == .mgdL ? .mgdL : .mmolL)
    }

    func getInsulinSensitivityItems() -> [TherapySettingsEditor.Item] {
        provider.insulinSensitivityProfile.sensitivities
            .map { TherapySettingsEditor.Item(time: TimeInterval($0.offset * 60), value: $0.sensitivity) }
    }

    @MainActor func saveInsulinSensitivityItems(_ items: [TherapySettingsEditor.Item]) {
        let profile = InsulinSensitivities(
            units: .mgdL,
            userPreferredUnits: .mgdL,
            sensitivities: items.map { $0.asInsulinSensitivityEntry() }
        )

        provider.saveInsulinSensitivityProfile(profile)
        info(.settings, "Insulin sensitivity schedule saved with \(items.count) entries")

        broadcaster.notify(InsulinSensitivitiesObserver.self, on: .main) {
            $0.insulinSensitivitiesDidChange(profile)
        }
    }
}
