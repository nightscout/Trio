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

        func deleteCarbsFromNightscout(withID id: String) {
            Task {
                await nightscoutManager.deleteCarbs(withID: id)
            }
        }

        func deleteInsulin(with treatmentObjectID: NSManagedObjectID) async {
            let taskContext = CoreDataStack.shared.newTaskContext()

            await taskContext.perform {
                do {
                    guard let treatmentToDelete = try taskContext.existingObject(with: treatmentObjectID) as? PumpEventStored
                    else {
                        debug(.default, "Could not cast the object to PumpEventStored")
                        return
                    }

                    // Delete Insulin from Nightscout
                    if let id = treatmentToDelete.id {
                        self.deleteInsulinFromNightscout(withID: id)
                    }

                    // TODO: - Rewrite healthkit implementation

//                    let id = treatmentToDelete.id
//                    self.healthkitManager.deleteInsulin(syncID: id)

                    taskContext.delete(treatmentToDelete)
                    try taskContext.save()

                    debug(.default, "Successfully deleted the treatment object.")
                } catch {
                    debug(.default, "Failed to delete the treatment object: \(error.localizedDescription)")
                }
            }
        }

        func deleteInsulinFromNightscout(withID id: String) {
            Task {
                await nightscoutManager.deleteInsulin(withID: id)
            }
        }

        func deleteManualGlucose(withID id: String) {
            Task {
                await nightscoutManager.deleteManualGlucose(withID: id)
            }
        }
    }
}
