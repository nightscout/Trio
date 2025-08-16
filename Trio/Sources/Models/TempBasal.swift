import Foundation

struct TempBasal: JSON {
    let duration: Int
    let rate: Decimal
    let temp: TempType
    let timestamp: Date
}
