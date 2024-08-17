import Foundation
import HealthKit
import LoopKit

struct BloodGlucose: JSON, Identifiable, Hashable {
    enum Direction: String, JSON {
        case tripleUp = "TripleUp"
        case doubleUp = "DoubleUp"
        case singleUp = "SingleUp"
        case fortyFiveUp = "FortyFiveUp"
        case flat = "Flat"
        case fortyFiveDown = "FortyFiveDown"
        case singleDown = "SingleDown"
        case doubleDown = "DoubleDown"
        case tripleDown = "TripleDown"
        case none = "NONE"
        case notComputable = "NOT COMPUTABLE"
        case rateOutOfRange = "RATE OUT OF RANGE"
    }

    var _id = UUID().uuidString
    var id: String {
        _id
    }

    var sgv: Int?
    var direction: Direction?
    let date: Decimal
    let dateString: Date
    let unfiltered: Decimal?
    let filtered: Decimal?
    let noise: Int?
    var glucose: Int?

    let type: String?

    var activationDate: Date? = nil
    var sessionStartDate: Date? = nil
    var transmitterID: String? = nil

    var isStateValid: Bool { sgv ?? 0 >= 39 && noise ?? 1 != 4 }

    static func == (lhs: BloodGlucose, rhs: BloodGlucose) -> Bool {
        lhs.dateString == rhs.dateString
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(dateString)
    }
}

enum GlucoseUnits: String, JSON, Equatable {
    case mgdL = "mg/dL"
    case mmolL = "mmol/L"

    static let exchangeRate: Decimal = 0.0555
}

extension Int {
    var asMmolL: Decimal {
        FreeAPS.rounded(Decimal(self) * GlucoseUnits.exchangeRate, scale: 1, roundingMode: .plain)
    }
}

extension Decimal {
    var asMmolL: Decimal {
        FreeAPS.rounded(self * GlucoseUnits.exchangeRate, scale: 1, roundingMode: .plain)
    }

    var asMgdL: Decimal {
        FreeAPS.rounded(self / GlucoseUnits.exchangeRate, scale: 0, roundingMode: .plain)
    }
}

extension Double {
    var asMmolL: Decimal {
        FreeAPS.rounded(Decimal(self) * GlucoseUnits.exchangeRate, scale: 1, roundingMode: .plain)
    }

    var asMgdL: Decimal {
        FreeAPS.rounded(Decimal(self) / GlucoseUnits.exchangeRate, scale: 0, roundingMode: .plain)
    }
}

extension BloodGlucose: SavitzkyGolaySmoothable {
    var value: Double {
        get {
            Double(glucose ?? 0)
        }
        set {
            glucose = Int(newValue)
            sgv = Int(newValue)
        }
    }
}

extension BloodGlucose {
    func convertStoredGlucoseSample(device: HKDevice?) -> StoredGlucoseSample {
        StoredGlucoseSample(
            syncIdentifier: id,
            startDate: dateString.date,
            quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double(glucose!)),
            device: device
        )
    }
}
