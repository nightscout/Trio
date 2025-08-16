import Foundation

struct Battery: JSON {
    let percent: Int?
    let voltage: Decimal?
    let string: BatteryState
    let display: Bool?
}

enum BatteryState: String, JSON {
    case normal
    case low
    case unknown
    case error
}
