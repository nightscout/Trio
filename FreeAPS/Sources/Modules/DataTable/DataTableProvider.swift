import Foundation

extension DataTable {
    final class Provider: BaseProvider, DataTableProvider {
        @Injected() var nightscoutManager: NightscoutManager!
        @Injected() var healthkitManager: HealthKitManager!

        func pumpSettings() -> PumpSettings {
            storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
                ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
                ?? PumpSettings(insulinActionCurve: 6, maxBolus: 10, maxBasal: 2)
        }

        func deleteCarbs(_: CarbEntryStored) {
            // TODO: fix this and refactor nightscoutManager.deleteCarbs()
//            nightscoutManager.deleteCarbs(treatment, complexMeal: false)
        }

        func deleteInsulin(_ treatment: PumpEventStored) {
            nightscoutManager.deleteInsulin(at: treatment.timestamp ?? Date())
            let id = treatment.id
            healthkitManager.deleteInsulin(syncID: id)
        }

        func deleteManualGlucose(date: Date?) {
            nightscoutManager.deleteManualGlucose(at: date ?? .distantPast)
        }
    }
}
