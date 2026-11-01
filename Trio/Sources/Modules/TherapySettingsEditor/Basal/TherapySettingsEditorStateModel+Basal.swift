import Foundation

extension TherapySettingsEditor.StateModel {
    func getBasalValueOptions(unit _: TherapySettingsEditor.Unit) -> [Decimal] {
        provider.supportedBasalRates ?? stride(from: 5.0, to: 1001.0, by: 5.0)
            .map { ($0.decimal ?? .zero) / 100 }
    }

    func getBasalItems() -> [TherapySettingsEditor.Item] {
        provider.basalProfile.map { TherapySettingsEditor.Item(time: TimeInterval($0.minutes * 60), value: $0.rate) }
    }

    @MainActor func saveBasalItems(_ items: [TherapySettingsEditor.Item]) async throws {
        let profile = items.map { $0.asBasalProfileEntry() }

        try await provider.saveBasalProfile(profile)
        info(.settings, "Basal profile saved with \(items.count) entries")

        broadcaster.notify(BasalProfileObserver.self, on: .main) {
            $0.basalProfileDidChange(profile)
        }
    }
}
