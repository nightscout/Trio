import Foundation

struct Autotune: JSON, Equatable {
    var createdAt: Date?
    let basalProfile: [BasalProfileEntry]
    let sensitivity: Decimal
    let carbRatio: Decimal
}

extension Autotune {
    private enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case basalProfile = "basalprofile"
        case sensitivity = "sens"
        case carbRatio = "carb_ratio"
    }
}
