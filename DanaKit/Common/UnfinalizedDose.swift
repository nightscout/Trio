import Foundation
import LoopKit

public class UnfinalizedDose {
    public typealias RawValue = [String: Any]

    public let type: DoseType
    public let startDate: Date
    public let endDate: Date
    public let unit: DoseUnit
    public let value: Double
    public var deliveredUnits: Double = 0
    public let insulinType: InsulinType?
    public let automatic: Bool?

    public init(units: Double, duration: TimeInterval, activationType: BolusActivationType, insulinType: InsulinType) {
        var endTime = Date.now
        endTime.addTimeInterval(duration)

        type = .bolus
        unit = .units
        value = units
        startDate = Date.now
        endDate = endTime
        self.insulinType = insulinType
        automatic = activationType.isAutomatic
    }

    public func toDoseEntry(isMutable: Bool = false) -> DoseEntry {
        DoseEntry(
            type: .bolus,
            startDate: startDate,
            endDate: endDate,
            value: value,
            unit: .units,
            deliveredUnits: isMutable ? value : deliveredUnits,
            insulinType: insulinType,
            automatic: automatic,
            isMutable: isMutable
        )
    }
}
