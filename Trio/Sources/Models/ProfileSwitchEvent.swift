import Foundation

/// Records a therapy profile switch event for history tracking.
struct ProfileSwitchEvent: JSON, Identifiable, Equatable, Hashable {
    let id: UUID
    let fromProfileId: UUID?
    let fromProfileName: String?
    let toProfileId: UUID
    let toProfileName: String
    let switchedAt: Date
    let weekday: Weekday
    let reason: SwitchReason
    var acknowledged: Bool

    /// The reason for the profile switch
    enum SwitchReason: String, Codable {
        /// Automatic midnight switch based on day schedule
        case scheduled
        /// User manually activated a profile
        case manual
        /// User overrode the scheduled profile for the current day
        case manualOverride
    }

    init(
        id: UUID = UUID(),
        fromProfileId: UUID? = nil,
        fromProfileName: String? = nil,
        toProfileId: UUID,
        toProfileName: String,
        switchedAt: Date = Date(),
        weekday: Weekday = .today,
        reason: SwitchReason,
        acknowledged: Bool = false
    ) {
        self.id = id
        self.fromProfileId = fromProfileId
        self.fromProfileName = fromProfileName
        self.toProfileId = toProfileId
        self.toProfileName = toProfileName
        self.switchedAt = switchedAt
        self.weekday = weekday
        self.reason = reason
        self.acknowledged = acknowledged
    }

    /// Human-readable description of the switch reason
    var reasonDescription: String {
        switch reason {
        case .scheduled:
            return NSLocalizedString("Scheduled switch", comment: "Automatic scheduled profile switch")
        case .manual:
            return NSLocalizedString("Manual activation", comment: "User manually activated profile")
        case .manualOverride:
            return NSLocalizedString("Manual override", comment: "User overrode scheduled profile")
        }
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Codable

extension ProfileSwitchEvent {
    private enum CodingKeys: String, CodingKey {
        case id
        case fromProfileId = "from_profile_id"
        case fromProfileName = "from_profile_name"
        case toProfileId = "to_profile_id"
        case toProfileName = "to_profile_name"
        case switchedAt = "switched_at"
        case weekday
        case reason
        case acknowledged
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        fromProfileId = try container.decodeIfPresent(UUID.self, forKey: .fromProfileId)
        fromProfileName = try container.decodeIfPresent(String.self, forKey: .fromProfileName)
        toProfileId = try container.decode(UUID.self, forKey: .toProfileId)
        toProfileName = try container.decode(String.self, forKey: .toProfileName)
        switchedAt = try container.decode(Date.self, forKey: .switchedAt)

        let weekdayRawValue = try container.decode(Int.self, forKey: .weekday)
        weekday = Weekday(rawValue: weekdayRawValue) ?? .sunday

        reason = try container.decode(SwitchReason.self, forKey: .reason)
        acknowledged = try container.decode(Bool.self, forKey: .acknowledged)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(fromProfileId, forKey: .fromProfileId)
        try container.encodeIfPresent(fromProfileName, forKey: .fromProfileName)
        try container.encode(toProfileId, forKey: .toProfileId)
        try container.encode(toProfileName, forKey: .toProfileName)
        try container.encode(switchedAt, forKey: .switchedAt)
        try container.encode(weekday.rawValue, forKey: .weekday)
        try container.encode(reason, forKey: .reason)
        try container.encode(acknowledged, forKey: .acknowledged)
    }
}
