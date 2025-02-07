import Foundation

struct Glucose: JSON {
    let sgv: Int?
    let glucose: Int?
    let type: GlucoseType
    let noise: Int?
    let date: Date
    let filtered: Double?
    let direction: Direction?
}

enum GlucoseType: String, JSON {
    case sgv
    case cal
    case manual = "Manual"
}

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
