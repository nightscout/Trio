import Foundation

/// Basal rate tables matching what each pump kit reports, for tests that need a realistic
/// pump shape. `BasalRoundingDriverParityTests` pins these against the kits' own tables.
///
/// Built with `append(contentsOf:)` rather than a chain of `+`: a three-way `[Decimal]`
/// concatenation type-checks on Xcode 26.6 but exceeds the type-checker's budget on the
/// Xcode 26.2 that CI pins.
enum PumpRateTables {
    /// Dana: 0.01 U/hr flat, up to 3 U/hr.
    static let dana: [Decimal] = (0 ... 300).map { Decimal($0) / 100 }

    /// Omnipod Eros: 0.05 U/hr flat to 30, and no zero rate.
    static let omnipodEros: [Decimal] = (1 ... 600).map { Decimal($0) / 20 }

    /// Omnipod non-Eros and Medtrum: 0.05 U/hr flat to 30, zero allowed.
    static let flat: [Decimal] = (0 ... 600).map { Decimal($0) / 20 }

    /// Minimed pre-x23: 0.05 U/hr flat to 35.
    static let minimedPre23: [Decimal] = (0 ... 700).map { Decimal($0) / 20 }

    /// Minimed gen >= 23: 0.025 below 1 U/hr, 0.05 to 9.95, 0.1 above.
    static let minimedGen23: [Decimal] = {
        var rates: [Decimal] = (0 ... 39).map { Decimal($0) / 40 }
        rates.append(contentsOf: (20 ... 199).map { Decimal($0) / 20 })
        rates.append(contentsOf: (100 ... 350).map { Decimal($0) / 10 })
        return rates
    }()
}
