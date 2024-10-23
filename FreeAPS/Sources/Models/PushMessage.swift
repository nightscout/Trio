import Foundation

struct PushMessage: Codable, Sendable {
    var user: String
    var commandType: TrioRemoteControl.CommandType
    var bolusAmount: Decimal?
    var target: Int?
    var duration: Int?
    var carbs: Int?
    var protein: Int?
    var fat: Int?
    var sharedSecret: String
    var timestamp: TimeInterval
    var overrideName: String?
    var scheduledTime: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case aps
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
        case overrideName
        case scheduledTime = "scheduled_time"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(user, forKey: .user)
        try container.encode(commandType, forKey: .commandType)
        try container.encodeIfPresent(bolusAmount, forKey: .bolusAmount)
        try container.encodeIfPresent(target, forKey: .target)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(carbs, forKey: .carbs)
        try container.encodeIfPresent(protein, forKey: .protein)
        try container.encodeIfPresent(fat, forKey: .fat)
        try container.encode(sharedSecret, forKey: .sharedSecret)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(overrideName, forKey: .overrideName)
        if let scheduledTime = scheduledTime {
            try container.encode(scheduledTime, forKey: .scheduledTime)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = try container.decode(String.self, forKey: .user)
        commandType = try container.decode(TrioRemoteControl.CommandType.self, forKey: .commandType)
        bolusAmount = try container.decodeIfPresent(Decimal.self, forKey: .bolusAmount)
        target = try container.decodeIfPresent(Int.self, forKey: .target)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        carbs = try container.decodeIfPresent(Int.self, forKey: .carbs)
        protein = try container.decodeIfPresent(Int.self, forKey: .protein)
        fat = try container.decodeIfPresent(Int.self, forKey: .fat)
        sharedSecret = try container.decode(String.self, forKey: .sharedSecret)
        timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        overrideName = try container.decodeIfPresent(String.self, forKey: .overrideName)
        scheduledTime = try container.decodeIfPresent(TimeInterval.self, forKey: .scheduledTime)
    }

    init(
        user: String,
        commandType: TrioRemoteControl.CommandType,
        bolusAmount: Decimal? = nil,
        target: Int? = nil,
        duration: Int? = nil,
        carbs: Int? = nil,
        protein: Int? = nil,
        fat: Int? = nil,
        sharedSecret: String,
        timestamp: TimeInterval,
        overrideName: String? = nil,
        scheduledTime: TimeInterval? = nil
    ) {
        self.user = user
        self.commandType = commandType
        self.bolusAmount = bolusAmount
        self.target = target
        self.duration = duration
        self.carbs = carbs
        self.protein = protein
        self.fat = fat
        self.sharedSecret = sharedSecret
        self.timestamp = timestamp
        self.overrideName = overrideName
        self.scheduledTime = scheduledTime
    }

    func humanReadableDescription() -> String {
        var description = "User: \(user). Command Type: \(commandType.description). "

        if let override = overrideName {
            description += "Override Name: \(override). "
        }

        switch commandType {
        case .bolus:
            if let amount = bolusAmount {
                description += "Bolus Amount: \(amount) units."
            } else {
                description += "Bolus Amount: unknown."
            }
        case .tempTarget:
            let targetDesc = target != nil ? "\(target!) mg/dL" : "unknown target"
            let durationDesc = duration != nil ? "\(duration!) minutes" : "unknown duration"
            description += "Temp Target: \(targetDesc), Duration: \(durationDesc)."
        case .cancelTempTarget:
            description += "Cancel Temp Target command."
        case .meal:
            let carbsDesc = carbs != nil ? "\(carbs!)g carbs" : "unknown carbs"
            let fatDesc = fat != nil ? "\(fat!)g fat" : "unknown fat"
            let proteinDesc = protein != nil ? "\(protein!)g protein" : "unknown protein"
            description += "Meal with \(carbsDesc), \(fatDesc), \(proteinDesc)."
        case .startOverride:
            if let override = overrideName {
                description += "Start Override: \(override)."
            } else {
                description += "Start Override: unknown override name."
            }
        case .cancelOverride:
            description += "Cancel Override command."
        }

        if let scheduledTime = scheduledTime {
            let date = Date(timeIntervalSince1970: scheduledTime)
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            let dateString = formatter.string(from: date)
            description += " Scheduled for: \(dateString)."
        }

        return description
    }
}
