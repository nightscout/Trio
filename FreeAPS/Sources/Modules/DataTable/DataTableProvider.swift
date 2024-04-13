import Foundation

extension DataTable {
    final class Provider: BaseProvider, DataTableProvider {
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!
        @Injected() var tempTargetsStorage: TempTargetsStorage!
        @Injected() var glucoseStorage: GlucoseStorage!
        @Injected() var carbsStorage: CarbsStorage!
        @Injected() var nightscoutManager: NightscoutManager!
        @Injected() var healthkitManager: HealthKitManager!

        func pumpHistory() -> [PumpHistoryEvent] {
            pumpHistoryStorage.recent()
        }

        func tempTargets() -> [TempTarget] {
            tempTargetsStorage.recent()
        }

        func carbs() -> [CarbsEntry] {
            carbsStorage.recent()
        }

        func fpus() -> [CarbsEntry] {
            carbsStorage.recent()
        }

        func deleteCarbs(_ treatement: Treatment) {
            nightscoutManager.deleteCarbs(
                at: treatement.date,
                isFPU: treatement.isFPU,
                fpuID: treatement.fpuID,
                syncID: treatement.id
            )
        }

        func deleteInsulin(_ treatement: Treatment) {
            nightscoutManager.deleteInsulin(at: treatement.date)
            if let id = treatement.idPumpEvent {
                healthkitManager.deleteInsulin(syncID: id)
            }
        }

        func glucose() -> [BloodGlucose] {
            glucoseStorage.recent().sorted { $0.date > $1.date }
        }

        func deleteGlucose(id: String) {
            glucoseStorage.removeGlucose(ids: [id])
            healthkitManager.deleteGlucose(syncID: id)
        }
    }
}
