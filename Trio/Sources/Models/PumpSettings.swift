import Foundation

public struct PumpSettings: JSON {
    public let insulinActionCurve: Decimal
    public let maxBolus: Decimal
    public let maxBasal: Decimal

    public init(insulinActionCurve: Decimal, maxBolus: Decimal, maxBasal: Decimal) {
        self.insulinActionCurve = insulinActionCurve
        self.maxBolus = maxBolus
        self.maxBasal = maxBasal
    }
}

extension PumpSettings {
    private enum CodingKeys: String, CodingKey {
        case insulinActionCurve = "insulin_action_curve"
        case maxBolus
        case maxBasal
    }
}
