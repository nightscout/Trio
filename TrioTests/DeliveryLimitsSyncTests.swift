import Foundation
import HealthKit
import LoopKit
import Testing

@testable import Trio

/// Covers `BaseDeviceDataManager.deliveryLimits(from:)`: the mapping from the user's configured
/// pump settings to the delivery limits synced to the pump manager.
@Suite("Delivery Limits Sync Tests") struct DeliveryLimitsSyncTests {
    private let basalUnit = HKUnit.internationalUnitsPerHour
    private let bolusUnit = HKUnit.internationalUnit()

    private func makeSettings(maxBasal: Decimal, maxBolus: Decimal) -> PumpSettings {
        PumpSettings(insulinActionCurve: 6, maxBolus: maxBolus, maxBasal: maxBasal)
    }

    @Test("maxBasal maps to maximumBasalRate in U/hr") func testMaxBasalMapping() {
        let settings = makeSettings(maxBasal: 5.0, maxBolus: 10.0)

        let limits = BaseDeviceDataManager.deliveryLimits(from: settings)

        #expect(limits.maximumBasalRate?.doubleValue(for: basalUnit) == 5.0)
    }

    @Test("maxBolus maps to maximumBolus in U") func testMaxBolusMapping() {
        let settings = makeSettings(maxBasal: 5.0, maxBolus: 10.0)

        let limits = BaseDeviceDataManager.deliveryLimits(from: settings)

        #expect(limits.maximumBolus?.doubleValue(for: bolusUnit) == 10.0)
    }

    /// The derived limit must be the user's configured value, not the `PumpInitialSettings` default.
    @Test("User-configured limit is preserved, not collapsed to the 2 U/hr default") func testDoesNotFallBackToDefault() {
        let configuredMaxBasal: Decimal = 3.0
        let defaultMaxBasal = PumpConfig.PumpInitialSettings.default.maxBasalRateUnitsPerHour

        let settings = makeSettings(maxBasal: configuredMaxBasal, maxBolus: 10.0)
        let limits = BaseDeviceDataManager.deliveryLimits(from: settings)

        #expect(limits.maximumBasalRate?.doubleValue(for: basalUnit) == Double(configuredMaxBasal))
        #expect(limits.maximumBasalRate?.doubleValue(for: basalUnit) != defaultMaxBasal)
    }

    /// The derived limit must be the user's configured value, not the `PumpInitialSettings` default.
    @Test("User-configured bolus limit is preserved, not collapsed to the default") func testBolusDoesNotFallBackToDefault() {
        let configuredMaxBolus: Decimal = 25.0
        let defaultMaxBolus = PumpConfig.PumpInitialSettings.default.maxBolusUnits

        let settings = makeSettings(maxBasal: 3.0, maxBolus: configuredMaxBolus)
        let limits = BaseDeviceDataManager.deliveryLimits(from: settings)

        #expect(limits.maximumBolus?.doubleValue(for: bolusUnit) == Double(configuredMaxBolus))
        #expect(limits.maximumBolus?.doubleValue(for: bolusUnit) != defaultMaxBolus)
    }
}
