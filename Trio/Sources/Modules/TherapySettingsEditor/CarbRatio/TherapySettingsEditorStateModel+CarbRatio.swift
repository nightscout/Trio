import Foundation
import Swinject

extension TherapySettingsEditor.StateModel {
    func getCarbRatioValueOptions(unit _: TherapySettingsEditor.Unit) -> [Decimal] {
        stride(from: 10.0, to: 501.0, by: 1.0).map { ($0.decimal ?? .zero) / 10 }
    }

    func getCarbRatioItems() -> [TherapySettingsEditor.Item] {
        provider.carbRatioProfile.schedule.map { TherapySettingsEditor.Item(time: TimeInterval($0.offset * 60), value: $0.ratio) }
    }

    @MainActor func saveCarbRatioItems(_ items: [TherapySettingsEditor.Item]) {
        let profile = CarbRatios(units: .grams, schedule: items.map { $0.asCarbRatioEntry() })

        provider.saveCarbRatioProfile(profile)

        broadcaster.notify(CarbRatiosObserver.self, on: .main) {
            $0.carbRatiosDidChange(profile)
        }
    }
}
