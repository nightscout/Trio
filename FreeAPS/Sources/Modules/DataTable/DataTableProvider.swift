import CoreData
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

        func deleteInsulin(with treatmentObjectID: NSManagedObjectID) {
            let taskContext = CoreDataStack.shared.newTaskContext()

            taskContext.perform {
                do {
                    guard let treatmentToDelete = try taskContext.existingObject(with: treatmentObjectID) as? PumpEventStored
                    else {
                        debug(.default, "Could not cast the object to PumpEventStored")
                        return
                    }
                    self.nightscoutManager.deleteInsulin(at: treatmentToDelete.timestamp ?? Date())
                    let id = treatmentToDelete.id
                    self.healthkitManager.deleteInsulin(syncID: id)

                    taskContext.delete(treatmentToDelete)
                    try taskContext.save()

                    debug(.default, "Successfully deleted the treatment object.")
                } catch {
                    debug(.default, "Failed to delete the treatment object: \(error.localizedDescription)")
                }
            }
        }

        func deleteManualGlucose(date: Date?) {
            nightscoutManager.deleteManualGlucose(at: date ?? .distantPast)
        }
    }
}
