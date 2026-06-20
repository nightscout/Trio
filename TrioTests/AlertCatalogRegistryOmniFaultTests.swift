import Foundation
import LoopKit
import Testing

@testable import Trio

/// Pins `AlertCatalogRegistry.lookup` behavior for Omni pod-fault identifiers.
/// `OmniPumpManager` builds `Alert.Identifier` from the formatted
/// `FaultEventCode.description` string ("Fault Event Code 0xNN: ..."), so the
/// registry has to parse the hex code out of that prefix at lookup time.
@Suite("AlertCatalogRegistry — Omni pod-fault hex parser") struct AlertCatalogRegistryOmniFaultTests {
    private func omniFaultID(_ desc: String) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: "Omni:pumpFault", alertIdentifier: desc)
    }

    @Test("0x14 → occlusion concept, critical, Pod Occlusion title") func code0x14Occlusion() {
        let entry = AlertCatalogRegistry.lookup(omniFaultID("Fault Event Code 0x14: Occluded"))
        #expect(entry?.concept == .occlusion)
        #expect(entry?.interruptionLevel == .critical)
        #expect(entry?.title == "Pod Occlusion")
    }

    @Test("0x18 → reservoirEmpty concept, critical") func code0x18ReservoirEmpty() {
        let entry = AlertCatalogRegistry.lookup(omniFaultID("Fault Event Code 0x18: Reservoir empty"))
        #expect(entry?.concept == .reservoirEmpty)
        #expect(entry?.interruptionLevel == .critical)
    }

    @Test("0x1C → deviceExpired concept, timeSensitive") func code0x1CExpired() {
        let entry = AlertCatalogRegistry.lookup(
            omniFaultID("Fault Event Code 0x1c: Exceeded maximum Pod life of 80 hours")
        )
        #expect(entry?.concept == .deviceExpired)
        #expect(entry?.interruptionLevel == .timeSensitive)
    }

    @Test("Unmapped fault code falls back to generic hardwareFault") func unknownCodeFallback() {
        let entry = AlertCatalogRegistry.lookup(omniFaultID("Fault Event Code 0x42: Some internal fault"))
        #expect(entry?.concept == .hardwareFault)
        #expect(entry?.interruptionLevel == .critical)
        #expect(entry?.title == "Pod Fault")
    }

    @Test("Malformed hex (non-hex chars) falls back to hardwareFault") func malformedHex() {
        let entry = AlertCatalogRegistry.lookup(omniFaultID("Fault Event Code 0xZZ: garbled"))
        #expect(entry?.concept == .hardwareFault)
    }

    @Test("Truncated identifier still resolves to hardwareFault") func truncatedIdentifier() {
        let entry = AlertCatalogRegistry.lookup(omniFaultID("Fault Event Code 0x"))
        #expect(entry?.concept == .hardwareFault)
    }

    @Test("Non-Omni managerIdentifier is ignored by the fault parser") func wrongManagerIgnored() {
        let id = Alert.Identifier(managerIdentifier: "Dana", alertIdentifier: "Fault Event Code 0x14: Occluded")
        // Dana doesn't carry this slug in the catalog, so lookup is nil even
        // though the alert text matches the Omni pattern.
        #expect(AlertCatalogRegistry.lookup(id) == nil)
    }
}
