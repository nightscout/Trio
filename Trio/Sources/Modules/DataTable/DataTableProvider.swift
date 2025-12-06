import CoreData
import Foundation
import HealthKit

extension DataTable {
    final class Provider: BaseProvider, DataTableProvider {
        @Injected() var nightscoutManager: NightscoutManager!
        @Injected() var healthkitManager: HealthKitManager!
        @Injected() var tidepoolManager: TidepoolManager!

        func pumpSettings() -> PumpSettings {
            storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
                ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
                ?? PumpSettings(insulinActionCurve: 10, maxBolus: 10, maxBasal: 2)
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

        func deleteInsulinFromHealth(withSyncID id: String) {
            Task.detached { [weak self] in
                guard let self = self else { return }
                await self.healthkitManager.deleteInsulin(syncID: id)
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

        func deleteMealDataFromHealth(byID id: String, sampleType: HKSampleType) {
            Task.detached { [weak self] in
                guard let self = self else { return }
                await self.healthkitManager.deleteMealData(byID: id, sampleType: sampleType)
            }
        }

        func deleteInsulinFromTidepool(withSyncId id: String, amount: Decimal, at: Date) {
            tidepoolManager.deleteInsulin(withSyncId: id, amount: amount, at: at)
        }

        func deleteCarbsFromTidepool(withSyncId id: UUID, carbs: Decimal, at: Date, enteredBy: String) {
            tidepoolManager.deleteCarbs(withSyncId: id, carbs: carbs, at: at, enteredBy: enteredBy)
        }
    }
}
