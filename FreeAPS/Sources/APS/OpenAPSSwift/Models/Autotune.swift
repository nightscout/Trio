import Foundation

struct Autotune: Codable {
    var createdAt: Date?
    let basalProfile: [BasalProfileEntry]?
    let isfProfile: ComputedInsulinSensitivities?
    let sensitivity: Double
    let carbRatio: Double?
}

extension Autotune {
    private enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case basalProfile = "basalprofile"
        case sensitivity = "sens"
        case carbRatio = "carb_ratio"
        case isfProfile
    }
}
