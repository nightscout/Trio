import Foundation

extension InsulinSensitivities {
    func computedInsulinSensitivies() -> ComputedInsulinSensitivities {
        let sensitivities = self.sensitivities
            .map { ComputedInsulinSensitivityEntry(sensitivity: $0.sensitivity, offset: $0.offset, start: $0.start) }
        return ComputedInsulinSensitivities(units: units, userPreferredUnits: userPreferredUnits, sensitivities: sensitivities)
    }
}
