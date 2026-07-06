import CGMBLEKit
import Foundation
import G7SensorKit
import LibreTransmitter
import LoopKit
import Testing

@testable import Trio

@Suite("Trio Alerts: CGMManagerAlertOwnership") struct CGMManagerAlertOwnershipTests {
    @Test("nil manager + .none source → no owner") func noneSourceNoManager() {
        #expect(CGMManagerAlertOwnership.owningApp(manager: nil, sourceType: .none) == nil)
        #expect(!CGMManagerAlertOwnership.providesOwnGlucoseAlerts(manager: nil, sourceType: .none))
    }

    /// Pins the xDrip4iOS case that was missed before: .xdrip runs through
    /// AppGroupSource without a CGMManager instance, so the ownership check
    /// must trigger off the source type alone.
    @Test(".xdrip source → xDrip4iOS owner + xdripswift:// deep link") func xdripSourceWinsWithNilManager() {
        let app = CGMManagerAlertOwnership.owningApp(manager: nil, sourceType: .xdrip)
        #expect(app?.name == "xDrip4iOS")
        #expect(app?.deepLink == URL(string: "xdripswift://"))
        #expect(CGMManagerAlertOwnership.providesOwnGlucoseAlerts(manager: nil, sourceType: .xdrip))
    }

    @Test("nightscout / simulator / enlite sources → no owner") func nonOwnerSources() {
        for source in [CGMType.nightscout, .simulator, .enlite] {
            #expect(CGMManagerAlertOwnership.owningApp(manager: nil, sourceType: source) == nil)
        }
    }

    /// Each known manager type maps to a fixed (name, deepLink) pair. Pinning
    /// the strings here means a rename in CGMManagerAlertOwnership.swift
    /// surfaces as a failing test rather than a silent UI copy change.
    @Test("G6CGMManager → Dexcom G6 / One + dexcomg6://") func g6Mapping() {
        let manager = G6CGMManager(state: TransmitterManagerState(transmitterID: "TEST6A"))
        let app = CGMManagerAlertOwnership.owningApp(manager: manager, sourceType: .plugin)
        #expect(app?.name == "Dexcom G6 / One")
        #expect(app?.deepLink == URL(string: "dexcomg6://"))
    }

    @Test("G7CGMManager → Dexcom G7 / One+ + dexcomg7://") func g7Mapping() {
        let app = CGMManagerAlertOwnership.owningApp(manager: G7CGMManager(), sourceType: .plugin)
        #expect(app?.name == "Dexcom G7 / One+")
        #expect(app?.deepLink == URL(string: "dexcomg7://"))
    }

    @Test("G5CGMManager → Dexcom G5, no known deep link") func g5Mapping() {
        let manager = G5CGMManager(state: TransmitterManagerState(transmitterID: "TEST5A"))
        let app = CGMManagerAlertOwnership.owningApp(manager: manager, sourceType: .plugin)
        #expect(app?.name == "Dexcom G5")
        #expect(app?.deepLink == nil)
    }
}
