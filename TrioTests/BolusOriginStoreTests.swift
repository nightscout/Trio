import Foundation
import LoopKit
import Testing

@testable import Trio

@Suite("Bolus Origin Store Tests") struct BolusOriginStoreTests {
    /// Fresh file URL per test so tests never touch the app's real store and cannot interfere with each other.
    private func makeTemporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bolus_origins_\(UUID().uuidString).json")
    }

    @Test("displayName maps each origin") func displayNames() {
        #expect(BolusOrigin.remote.displayName == "Remote")
        #expect(BolusOrigin.watch.displayName == "Watch")
        #expect(BolusOrigin.manual.displayName == "Manual")
        #expect(BolusOrigin.shortcut.displayName == "Shortcut")
    }

    @Test("reference round-trips and is removable") func roundTrip() {
        let store = BolusOriginStore(fileURL: makeTemporaryFileURL())

        let reference = store.makeReference(for: .remote)
        #expect(store.origin(forReference: reference) == .remote)

        store.remove(reference: reference)
        #expect(store.origin(forReference: reference) == nil)
    }

    @Test("unknown reference resolves to nil") func unknownReference() {
        let store = BolusOriginStore(fileURL: makeTemporaryFileURL())
        #expect(store.origin(forReference: UUID()) == nil)
    }

    @Test("promotion re-keys a reference to a sync identifier") func promotion() {
        let store = BolusOriginStore(fileURL: makeTemporaryFileURL())

        let reference = store.makeReference(for: .watch)
        store.promoteReference(reference, toSyncIdentifier: "sync-id-1")

        #expect(store.origin(forReference: reference) == nil)
        #expect(store.origin(forSyncIdentifier: "sync-id-1") == .watch)

        // Promoting an already promoted (or unknown) reference must not disturb the promoted entry.
        store.promoteReference(reference, toSyncIdentifier: "sync-id-2")
        #expect(store.origin(forSyncIdentifier: "sync-id-1") == .watch)
        #expect(store.origin(forSyncIdentifier: "sync-id-2") == nil)

        store.remove(syncIdentifier: "sync-id-1")
        #expect(store.origin(forSyncIdentifier: "sync-id-1") == nil)
    }

    @Test("mappings survive a reload from disk") func persistence() {
        let fileURL = makeTemporaryFileURL()

        let reference = BolusOriginStore(fileURL: fileURL).makeReference(for: .shortcut)

        let reloaded = BolusOriginStore(fileURL: fileURL)
        #expect(reloaded.origin(forReference: reference) == .shortcut)
    }

    @Test("expired entries are dropped on load") func expiry() throws {
        let fileURL = makeTemporaryFileURL()
        let freshReference = UUID()
        let staleReference = UUID()

        // Write the store's JSON shape directly: one entry well past the 6h TTL, one fresh.
        let staleDate = Date().addingTimeInterval(-7 * 60 * 60).timeIntervalSinceReferenceDate
        let freshDate = Date().timeIntervalSinceReferenceDate
        let json = """
        {
            "\(staleReference.uuidString)": { "origin": "manual", "createdAt": \(staleDate) },
            "\(freshReference.uuidString)": { "origin": "remote", "createdAt": \(freshDate) }
        }
        """
        try json.data(using: .utf8)!.write(to: fileURL)

        let store = BolusOriginStore(fileURL: fileURL)
        #expect(store.origin(forReference: staleReference) == nil)
        #expect(store.origin(forReference: freshReference) == .remote)
    }

    @Test("corrupt store file is discarded, not fatal") func corruptFile() throws {
        let fileURL = makeTemporaryFileURL()
        try Data("not json".utf8).write(to: fileURL)

        let store = BolusOriginStore(fileURL: fileURL)
        #expect(store.origin(forReference: UUID()) == nil)

        // The store must still be usable (and re-persistable) afterwards.
        let reference = store.makeReference(for: .manual)
        #expect(BolusOriginStore(fileURL: fileURL).origin(forReference: reference) == .manual)
    }
}
