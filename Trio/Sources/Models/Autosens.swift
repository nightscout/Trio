import Foundation

struct Autosens: JSON {
    let ratio: Decimal
    let newisf: Decimal?
    var deviationsUnsorted: [Decimal]?
    var timestamp: Date?
    var error: String?
}
