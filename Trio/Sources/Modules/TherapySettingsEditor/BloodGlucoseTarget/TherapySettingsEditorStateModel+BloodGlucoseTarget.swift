import Foundation

extension TherapySettingsEditor.StateModel {
    func getBloodGlucoseTargetOptions(unit: TherapySettingsEditor.Unit) -> [Decimal] {
        let settingsProvider = PickerSettingsProvider.shared
        let glucoseSetting = PickerSetting(value: 110, step: 1, min: 72, max: 180, type: .glucose)
        return settingsProvider.generatePickerValues(from: glucoseSetting, units: unit == .mgdL ? .mgdL : .mmolL)
    }

    func getBloodGlucoseTargetItems() -> [TherapySettingsEditor.Item] {
        provider.bloodGlucoseTargetProfile.targets
            .map { TherapySettingsEditor.Item(time: TimeInterval($0.offset * 60), value: $0.low) }
    }

    @MainActor func saveBloodGlucoseTargetItems(_ items: [TherapySettingsEditor.Item]) {
        let profile = BGTargets(
            units: .mgdL,
            userPreferredUnits: .mgdL,
            targets: items.map { $0.asBGTargetEntry() }
        )

        provider.saveBloodGlucoseTargetProfile(profile)
        info(.settings, "Glucose target schedule saved with \(items.count) entries")

        broadcaster.notify(BGTargetsObserver.self, on: .main) {
            $0.bgTargetsDidChange(profile)
        }
    }
}
