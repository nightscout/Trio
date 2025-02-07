import Foundation

struct PumpStatus: JSON, Equatable {
    let status: StatusType
    let bolusing: Bool
    let suspended: Bool
    var timestamp: Date?
}

enum StatusType: String, JSON {
    case normal
    case suspended
    case bolusing
}
