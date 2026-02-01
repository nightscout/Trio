import Foundation

struct InsulinSensitivityTiers: JSON, Equatable {
    var enabled: Bool
    var tiers: [InsulinSensitivityTier]
}

extension InsulinSensitivityTiers {
    private enum CodingKeys: String, CodingKey {
        case enabled
        case tiers
    }
}

extension InsulinSensitivityTiers: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var result = InsulinSensitivityTiers(enabled: false, tiers: InsulinSensitivityTier.defaultTiers)

        if let enabled = try? container.decode(Bool.self, forKey: .enabled) {
            result.enabled = enabled
        }

        if let tiers = try? container.decode([InsulinSensitivityTier].self, forKey: .tiers) {
            result.tiers = tiers
        }

        self = result
    }
}

struct InsulinSensitivityTier: JSON, Equatable, Identifiable {
    var id: UUID = UUID()
    /// Lower bound of BG range in mg/dL
    var bgMin: Decimal
    /// Upper bound of BG range in mg/dL
    var bgMax: Decimal
    /// Multiplier to apply to profile ISF (e.g. 0.8 = 80% of normal ISF = more aggressive)
    var isfMultiplier: Decimal

    static let defaultTiers: [InsulinSensitivityTier] = [
        InsulinSensitivityTier(bgMin: 0, bgMax: 70, isfMultiplier: 1.2),
        InsulinSensitivityTier(bgMin: 70, bgMax: 140, isfMultiplier: 1.0),
        InsulinSensitivityTier(bgMin: 140, bgMax: 200, isfMultiplier: 0.9),
        InsulinSensitivityTier(bgMin: 200, bgMax: 250, isfMultiplier: 0.8),
        InsulinSensitivityTier(bgMin: 250, bgMax: 400, isfMultiplier: 0.7)
    ]
}

extension InsulinSensitivityTier {
    private enum CodingKeys: String, CodingKey {
        case bgMin = "bg_min"
        case bgMax = "bg_max"
        case isfMultiplier = "isf_multiplier"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        bgMin = try container.decode(Decimal.self, forKey: .bgMin)
        bgMax = try container.decode(Decimal.self, forKey: .bgMax)
        isfMultiplier = try container.decode(Decimal.self, forKey: .isfMultiplier)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bgMin, forKey: .bgMin)
        try container.encode(bgMax, forKey: .bgMax)
        try container.encode(isfMultiplier, forKey: .isfMultiplier)
    }
}
