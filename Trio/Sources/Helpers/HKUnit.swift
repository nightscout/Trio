import HealthKit

extension HKUnit {
    static let milligramsPerDeciliter: HKUnit = {
        HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
    }()

    static let millimolesPerLiter: HKUnit = {
        HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: .liter())
    }()

    static let internationalUnitsPerHour: HKUnit = {
        HKUnit.internationalUnit().unitDivided(by: .hour())
    }()

    static let gramsPerUnit: HKUnit = {
        HKUnit.gram().unitDivided(by: .internationalUnit())
    }()

    var foundationUnit: Unit? {
        if self == HKUnit.milligramsPerDeciliter {
            return UnitConcentrationMass.milligramsPerDeciliter
        }

        if self == HKUnit.millimolesPerLiter {
            return UnitConcentrationMass.millimolesPerLiter(withGramsPerMole: HKUnitMolarMassBloodGlucose)
        }

        if self == HKUnit.gram() {
            return UnitMass.grams
        }

        return nil
    }

    /// The smallest value expected to be visible on a chart
    var chartableIncrement: Double {
        if self == .milligramsPerDeciliter {
            return 1
        } else {
            return 1 / 25
        }
    }

    var localizedShortUnitString: String {
        if self == HKUnit.millimolesPerLiter {
            return NSLocalizedString("mmol/L", comment: "The short unit display string for millimoles of glucose per liter")
        } else if self == .milligramsPerDeciliter {
            return NSLocalizedString("mg/dL", comment: "The short unit display string for milligrams of glucose per decilter")
        } else if self == .internationalUnit() {
            return NSLocalizedString("U", comment: "The short unit display string for international units of insulin")
        } else if self == .gram() {
            return NSLocalizedString("g", comment: "The short unit display string for grams")
        } else {
            return String(describing: self)
        }
    }
}
