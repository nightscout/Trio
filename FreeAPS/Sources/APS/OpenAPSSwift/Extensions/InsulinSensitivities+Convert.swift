import Foundation

extension InsulinSensitivities {
    func computedInsulinSensitivies() -> ComputedInsulinSensitivities {
        let sensitivities = self.sensitivities
            .map { ComputedInsulinSensitivityEntry(sensitivity: $0.sensitivity, offset: $0.offset, start: $0.start) }
        return ComputedInsulinSensitivities(units: units, userPreferredUnits: userPreferredUnits, sensitivities: sensitivities)
    }

    func inMgDl() -> InsulinSensitivities {
        switch units {
        case .mgdL:
            return self
        case .mmolL:
            let sensitivities = self.sensitivities
                .map { InsulinSensitivityEntry(sensitivity: $0.sensitivity * 18, offset: $0.offset, start: $0.start) }
            return InsulinSensitivities(
                units: .mgdL,
                userPreferredUnits: userPreferredUnits,
                sensitivities: sensitivities
            )
        }
    }
}
