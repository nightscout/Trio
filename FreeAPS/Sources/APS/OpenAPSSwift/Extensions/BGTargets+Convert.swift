import Foundation

extension BGTargets {
    func inMgDl() -> BGTargets {
        switch units {
        case .mgdL:
            return self
        case .mmolL:
            let targets = targets
                .map { BGTargetEntry(low: $0.low * 18, high: $0.high * 18, start: $0.start, offset: $0.offset) }
            return BGTargets(units: .mgdL, userPreferredUnits: userPreferredUnits, targets: targets)
        }
    }
}
