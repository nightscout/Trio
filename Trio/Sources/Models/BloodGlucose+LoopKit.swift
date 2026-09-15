import Foundation
import HealthKit
import LoopKit

// LoopKit/HealthKit adapter for `BloodGlucose`.
//
// Kept out of `BloodGlucose.swift` so that the model itself stays Foundation-only and can be
// compiled by the algorithm package (see `AlgorithmPackage/Package.swift`). Consumed by
// `GlucoseStorage`.
extension BloodGlucose {
    func convertStoredGlucoseSample(isManualGlucose: Bool) -> StoredGlucoseSample {
        StoredGlucoseSample(
            syncIdentifier: id,
            startDate: dateString.date,
            quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double(glucose!)),
            wasUserEntered: isManualGlucose,
            device: HKDevice.local()
        )
    }
}
