import Foundation

struct PushMessage: Decodable {
    var user: String
    var commandType: String
    var bolusAmount: Decimal?
    var target: Int?
    var duration: Int?
    var carbs: Int?
    var protein: Int?
    var fat: Int?
    var sharedSecret: String
    var timestamp: TimeInterval

    enum CodingKeys: String, CodingKey {
        case user
        case commandType = "command_type"
        case bolusAmount = "bolus_amount"
        case target
        case duration
        case carbs
        case protein
        case fat
        case sharedSecret = "shared_secret"
        case timestamp
    }
}

extension PushMessage {
    func humanReadableDescription() -> String {
        var description = "User: \(user). Command Type: \(commandType). "
        switch commandType {
        case "bolus":
            if let amount = bolusAmount {
                description += "Bolus Amount: \(amount) units."
            } else {
                description += "Bolus Amount: unknown."
            }
        case "temp_target":
            let targetDescription = target != nil ? "\(target!) mg/dL" : "unknown target"
            let durationDescription = duration != nil ? "\(duration!) minutes" : "unknown duration"
            description += "Temp Target: \(targetDescription), Duration: \(durationDescription)."
        case "cancel_temp_target":
            description += "Cancel Temp Target command."
        case "meal":
            let carbsDescription = carbs != nil ? "\(carbs!)g carbs" : "unknown carbs"
            let fatDescription = fat != nil ? "\(fat!)g fat" : "unknown fat"
            let proteinDescription = protein != nil ? "\(protein!)g protein" : "unknown protein"
            description += "Meal with \(carbsDescription), \(fatDescription), \(proteinDescription)."
        default:
            description += "Unsupported command type."
        }
        return description
    }
}
