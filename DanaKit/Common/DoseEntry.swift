import Foundation
import LoopKit

public extension DoseEntry {
    static func bolus(
        units: Double,
        deliveredUnits: Double,
        duration: TimeInterval,
        activationType: BolusActivationType,
        insulinType: InsulinType,
        startDate: Date = Date.now
    ) -> DoseEntry {
        var endTime = Date.now
        endTime.addTimeInterval(duration)

        return DoseEntry(
            type: .bolus,
            startDate: startDate,
            endDate: endTime,
            value: units,
            unit: .units,
            deliveredUnits: deliveredUnits,
            insulinType: insulinType,
            automatic: activationType.isAutomatic,
            manuallyEntered: activationType == .manualNoRecommendation,
            isMutable: false
        )
    }

    static func tempBasal(
        absoluteUnit: Double,
        duration: TimeInterval,
        insulinType: InsulinType,
        startDate: Date = Date.now
    ) -> DoseEntry {
        DoseEntry(
            type: .tempBasal,
            startDate: startDate,
            endDate: startDate + duration,
            value: absoluteUnit,
            unit: .unitsPerHour,
            insulinType: insulinType
        )
    }

    static func basal(rate: Double, insulinType: InsulinType, startDate: Date = Date.now) -> DoseEntry {
        DoseEntry(
            type: .basal,
            startDate: startDate,
            value: rate,
            unit: .unitsPerHour,
            insulinType: insulinType
        )
    }

    static func resume(insulinType: InsulinType, resumeDate: Date = Date.now) -> DoseEntry {
        DoseEntry(
            resumeDate: resumeDate,
            insulinType: insulinType
        )
    }

    static func suspend(suspendDate: Date = Date.now) -> DoseEntry {
        DoseEntry(suspendDate: suspendDate)
    }
}
