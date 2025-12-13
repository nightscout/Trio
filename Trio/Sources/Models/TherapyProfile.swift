import Foundation

/// A complete therapy profile containing all settings for insulin delivery and glucose management.
/// Users can create multiple profiles for different scenarios (e.g., weekday vs weekend).
struct TherapyProfile: JSON, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var activeDays: Set<Weekday>
    var basalProfile: [BasalProfileEntry]
    var insulinSensitivities: InsulinSensitivities
    var carbRatios: CarbRatios
    var bgTargets: BGTargets
    var isDefault: Bool
    var createdAt: Date
    var lastModified: Date

    /// Maximum number of profiles allowed
    static let maxProfiles = 10

    init(
        id: UUID = UUID(),
        name: String,
        activeDays: Set<Weekday> = [],
        basalProfile: [BasalProfileEntry] = [],
        insulinSensitivities: InsulinSensitivities,
        carbRatios: CarbRatios,
        bgTargets: BGTargets,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        lastModified: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.activeDays = activeDays
        self.basalProfile = basalProfile
        self.insulinSensitivities = insulinSensitivities
        self.carbRatios = carbRatios
        self.bgTargets = bgTargets
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.lastModified = lastModified
    }

    /// Creates a copy of this profile with a new ID and name
    func copy(withName newName: String) -> TherapyProfile {
        TherapyProfile(
            id: UUID(),
            name: newName,
            activeDays: [],
            basalProfile: basalProfile,
            insulinSensitivities: insulinSensitivities,
            carbRatios: carbRatios,
            bgTargets: bgTargets,
            isDefault: false,
            createdAt: Date(),
            lastModified: Date()
        )
    }

    /// Updates the lastModified timestamp
    mutating func touch() {
        lastModified = Date()
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Equatable

    static func == (lhs: TherapyProfile, rhs: TherapyProfile) -> Bool {
        lhs.id == rhs.id &&
            lhs.name == rhs.name &&
            lhs.activeDays == rhs.activeDays &&
            lhs.isDefault == rhs.isDefault &&
            lhs.createdAt == rhs.createdAt &&
            lhs.lastModified == rhs.lastModified
    }
}

// MARK: - Codable

extension TherapyProfile {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case activeDays = "active_days"
        case basalProfile = "basal_profile"
        case insulinSensitivities = "insulin_sensitivities"
        case carbRatios = "carb_ratios"
        case bgTargets = "bg_targets"
        case isDefault = "is_default"
        case createdAt = "created_at"
        case lastModified = "last_modified"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        // Decode activeDays as array of raw values, convert to Set<Weekday>
        let dayValues = try container.decode([Int].self, forKey: .activeDays)
        activeDays = Set(dayValues.compactMap { Weekday(rawValue: $0) })

        basalProfile = try container.decode([BasalProfileEntry].self, forKey: .basalProfile)
        insulinSensitivities = try container.decode(InsulinSensitivities.self, forKey: .insulinSensitivities)
        carbRatios = try container.decode(CarbRatios.self, forKey: .carbRatios)
        bgTargets = try container.decode(BGTargets.self, forKey: .bgTargets)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)

        // Encode activeDays as array of raw values
        let dayValues = activeDays.map(\.rawValue).sorted()
        try container.encode(dayValues, forKey: .activeDays)

        try container.encode(basalProfile, forKey: .basalProfile)
        try container.encode(insulinSensitivities, forKey: .insulinSensitivities)
        try container.encode(carbRatios, forKey: .carbRatios)
        try container.encode(bgTargets, forKey: .bgTargets)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastModified, forKey: .lastModified)
    }
}

// MARK: - Observer Protocol

protocol TherapyProfileObserver {
    func activeProfileDidChange(_ profile: TherapyProfile)
}
