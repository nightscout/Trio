import Foundation
import Swinject
import Testing

@testable import Trio

@Suite("Bolus Origin Store Tests", .serialized) struct BolusOriginStoreTests {
    /// Builds a store backed by real on-disk `FileStorage`, so persistence across instances is exercised.
    private func makeStore() -> BolusOriginStore {
        let container = Container()
        container.register(FileStorage.self) { _ in BaseFileStorage() }
        return BaseBolusOriginStore(resolver: container)
    }

    @Test("displayName maps each origin") func displayNames() {
        #expect(BolusOrigin.smb.displayName == "SMB")
        #expect(BolusOrigin.remote.displayName == "Remote")
        #expect(BolusOrigin.watch.displayName == "Watch")
        #expect(BolusOrigin.manual.displayName == "Manual")
        #expect(BolusOrigin.shortcut.displayName == "Shortcut")
    }

    @Test("reference round-trips and can be removed") func roundTrip() {
        let store = makeStore()

        let reference = store.makeReference(for: .remote)
        #expect(store.origin(for: reference) == .remote)

        store.remove(reference)
        #expect(store.origin(for: reference) == nil)
    }

    @Test("unknown reference resolves to nil") func unknownReference() {
        let store = makeStore()
        #expect(store.origin(for: UUID()) == nil)
    }

    /// The reference is persisted, so a dose reported after an app restart (a fresh store instance) still
    /// resolves its origin — this is the whole point of round-tripping the reference through the pump.
    @Test("mapping survives a fresh store instance") func persistsAcrossInstances() {
        let reference = makeStore().makeReference(for: .watch)

        let reloaded = makeStore()
        #expect(reloaded.origin(for: reference) == .watch)

        reloaded.remove(reference)
        #expect(makeStore().origin(for: reference) == nil)
    }
}
