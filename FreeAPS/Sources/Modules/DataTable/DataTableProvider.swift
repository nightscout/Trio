import CoreData
import Foundation

extension DataTable {
    final class Provider: BaseProvider, DataTableProvider {
        @Injected() var nightscoutManager: NightscoutManager!
        @Injected() var healthkitManager: HealthKitManager!
        @Injected() var tidepoolManager: TidepoolManager!

        func pumpSettings() -> PumpSettings {
            storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
                ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
                ?? PumpSettings(insulinActionCurve: 6, maxBolus: 10, maxBasal: 2)
        }

        func deleteCarbsFromNightscout(withID id: String) {
            Task.detached { [weak self] in
                guard let self = self else { return }
                await self.nightscoutManager.deleteCarbs(withID: id)
            }
        }

        func deleteInsulinFromNightscout(withID id: String) {
            Task.detached { [weak self] in
                guard let self = self else { return }
                await self.nightscoutManager.deleteInsulin(withID: id)
            }
        }

        func deleteManualGlucoseFromNightscout(withID id: String) {
            Task.detached { [weak self] in
                guard let self = self else { return }
                await self.nightscoutManager.deleteManualGlucose(withID: id)
            }
        }

        func deleteGlucoseFromHealth(withSyncID id: String) {
            Task.detached { [weak self] in
                guard let self = self else { return }
                await self.healthkitManager.deleteGlucose(syncID: id)
            }
        }
    }
}
