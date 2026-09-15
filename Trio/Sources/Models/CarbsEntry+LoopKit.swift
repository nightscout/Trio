import Foundation
import LoopKit

// LoopKit adapter for `CarbsEntry`.
//
// Kept out of `CarbsEntry.swift` so that the model itself stays Foundation-only and can be
// compiled by the algorithm package (see `AlgorithmPackage/Package.swift`). Consumed by
// `TidepoolManager`.
extension CarbsEntry {
    func convertSyncCarb(operation: LoopKit.Operation = .create) -> SyncCarbObject {
        SyncCarbObject(
            absorptionTime: nil,
            createdByCurrentApp: true,
            foodType: nil,
            grams: Double(carbs),
            startDate: createdAt,
            uuid: UUID(uuidString: id!),
            provenanceIdentifier: enteredBy ?? "Trio",
            syncIdentifier: id,
            syncVersion: nil,
            userCreatedDate: nil,
            userUpdatedDate: nil,
            userDeletedDate: nil,
            operation: operation,
            addedDate: nil,
            supercededDate: nil
        )
    }
}
