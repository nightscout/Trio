import Foundation
import LoopKit
import Testing

@testable import Trio

@Suite("Bolus Origin Store Tests", .serialized) struct BolusOriginStoreTests {
    @Test("displayName maps each origin") func displayNames() {
        #expect(BolusOrigin.smb.displayName == "SMB")
        #expect(BolusOrigin.remote.displayName == "Remote")
        #expect(BolusOrigin.watch.displayName == "Watch")
        #expect(BolusOrigin.manual.displayName == "Manual")
        #expect(BolusOrigin.shortcut.displayName == "Shortcut")
    }

    @Test("reference round-trips through the shared LoopKit store") func roundTrip() {
        let store = BolusOriginStore.shared

        let reference = store.makeReference(for: BolusOrigin.remote.rawValue)
        #expect(store.origin(forReference: reference).flatMap(BolusOrigin.init(rawValue:)) == .remote)

        store.remove(reference: reference)
        #expect(store.origin(forReference: reference) == nil)
    }

    @Test("unknown reference resolves to nil") func unknownReference() {
        #expect(BolusOriginStore.shared.origin(forReference: UUID()) == nil)
    }
}
