import Foundation

struct BGTargets: JSON {
    var units: GlucoseUnits
    var userPreferredUnits: GlucoseUnits
    var targets: [BGTargetEntry]
}

protocol BGTargetsObserver {
    func bgTargetsDidChange(_ bgTargets: BGTargets)
}

extension BGTargets {
    private enum CodingKeys: String, CodingKey {
        case units
        case userPreferredUnits = "user_preferred_units"
        case targets
    }
}

struct BGTargetEntry: JSON {
    let low: Decimal
    let high: Decimal
    let start: String
    let offset: Int
}
