import DanaKit
import Foundation
import MedtrumKit
import MinimedKit
import Testing

@testable import Trio

/// Pins `TempBasalFunctions.roundBasal` against the real pump kits' own rate tables, so the
/// algorithm and `PumpManager.roundToSupportedBasalRate` can never disagree about what the
/// paired pump can deliver. `RoundBasalTests` covers the same shapes arithmetically for the
/// algorithm-only SPM target, which cannot import the kits.
@Suite("Basal Rounding Driver Parity") struct BasalRoundingDriverParityTests {
    /// Mirrors `APSManager.supportedBasalRates`: the 3 dp normalisation is what keeps a
    /// `Double(n) / 20` table entry from landing just above the clean rate it represents.
    private func normalised(_ rates: [Double]) -> [Decimal] {
        rates.map { Decimal($0).rounded(scale: 3) }
    }

    private func rates(for table: [Double]) -> (algorithm: (Decimal) -> Decimal, driver: (Double) -> Double) {
        var profile = Profile()
        profile.supportedBasalRates = normalised(table)
        return (
            algorithm: { TempBasalFunctions.roundBasal(profile: profile, basalRate: $0) },
            // the shape every kit implements, and LoopKit's default
            driver: { unitsPerHour in table.last(where: { $0 <= unitsPerHour }) ?? 0 }
        )
    }

    /// Values chosen to land on, just below, and just above real table steps.
    private static let probes: [Decimal] = [
        0, 0.01, 0.024, 0.025, 0.03, 0.049, 0.05, 0.07, 0.5, 0.975, 0.99,
        1, 1.03, 1.23, 2.5, 3, 3.01, 5.375, 9.95, 10, 10.05, 10.06, 24.9, 30, 35, 40
    ]

    @Test("matches every kit's own table", arguments: [
        ("Minimed 723 (gen >= 23)", PumpModel.model723.supportedBasalRates),
        ("Minimed 522 (pre-x23)", PumpModel.model522.supportedBasalRates),
        ("Dana", DanaKitPumpManager.onboardingSupportedBasalRates),
        ("Medtrum", MedtrumPumpManager.onboardingSupportedBasalRates),
        // Pod's table is a local inside OmnipodKit's BasalDeliveryTable, so replicate Eros here
        ("Omnipod Eros", (1 ... 600).map { Double($0) / 20 })
    ]) func matchesDriver(pump: String, table: [Double]) {
        let (algorithm, driver) = rates(for: table)

        for probe in Self.probes {
            let mine = algorithm(probe)
            let theirs = Decimal(driver(Double(truncating: probe as NSNumber))).rounded(scale: 3)
            #expect(mine == theirs, "\(pump) disagrees at \(probe): algorithm \(mine), driver \(theirs)")
        }
    }

    /// The rate `APSManager.performBasal` hands over must be the *same* `Double` the driver's own
    /// table holds. `Double(truncating:)` lands below on 41 of Dana's 301 rates (0.07 becomes
    /// 0.06999999999999999), and since every table floors, that silently costs a full increment.
    @Test("the rate handed to the driver survives the Decimal to Double hop", arguments: [
        ("Minimed 723 (gen >= 23)", PumpModel.model723.supportedBasalRates),
        ("Minimed 522 (pre-x23)", PumpModel.model522.supportedBasalRates),
        ("Dana", DanaKitPumpManager.onboardingSupportedBasalRates),
        ("Medtrum", MedtrumPumpManager.onboardingSupportedBasalRates),
        ("Omnipod Eros", (1 ... 600).map { Double($0) / 20 })
    ]) func handedOverRateSurvivesConversion(pump: String, table: [Double]) {
        for entry in table {
            // what roundBasal returns: the injected table entry, an exact 3 dp Decimal
            let algorithmRate = Decimal(entry).rounded(scale: 3)
            // what performBasal sends
            let handedOver = algorithmRate.nearestDouble

            #expect(handedOver == entry, "\(pump): \(algorithmRate) converted to \(handedOver), table holds \(entry)")
            #expect(
                (table.last { $0 <= handedOver } ?? 0) == entry,
                "\(pump): the driver would floor \(handedOver) below \(entry)"
            )
        }
    }

    @Test("the lossy conversion this replaced really did drop an increment") func lossyConversionRegression() {
        // pins why nearestDouble exists, so nobody reverts it to Double(truncating:)
        let dana = DanaKitPumpManager.onboardingSupportedBasalRates
        for rate in [Decimal(7) / 100, Decimal(14) / 100, Decimal(199) / 100] {
            let lossy = Double(truncating: rate as NSNumber)
            #expect((dana.last { $0 <= lossy } ?? 0) != rate.nearestDouble)
            #expect((dana.last { $0 <= rate.nearestDouble } ?? 0) == rate.nearestDouble)
        }
    }

    @Test("every kit table is non-empty and normalises without collisions") func tablesNormaliseCleanly() {
        for table in [
            PumpModel.model723.supportedBasalRates,
            PumpModel.model522.supportedBasalRates,
            DanaKitPumpManager.onboardingSupportedBasalRates,
            MedtrumPumpManager.onboardingSupportedBasalRates
        ] {
            let rates = normalised(table)
            #expect(!rates.isEmpty)
            // 3 dp must not merge two distinct rates into one
            #expect(Set(rates).count == Set(table).count)
        }
    }
}
