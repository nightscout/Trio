import Foundation
import LoopKit
import Testing

@testable import Trio

/// Tests for `CarbsEntry.convertSyncCarb()`, the mapping used for Tidepool uploads.
@Suite("CarbsEntry LoopKit Conversion Tests") struct CarbsEntryLoopKitTests {
    private func entry(id: String?) -> CarbsEntry {
        CarbsEntry(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            actualDate: nil,
            carbs: 20,
            fat: nil,
            protein: nil,
            note: nil,
            enteredBy: CarbsEntry.local,
            isFPU: false,
            fpuID: nil
        )
    }

    @Test("An entry without id converts without a uuid or sync identifier") func testNilID() {
        let carb = entry(id: nil).convertSyncCarb()

        #expect(carb.uuid == nil)
        #expect(carb.syncIdentifier == nil)
    }

    @Test("A UUID id maps to uuid and sync identifier") func testUUIDID() {
        let id = "3D6BB81B-A387-4042-B0EC-BD38EF1A93C3"
        let carb = entry(id: id).convertSyncCarb()

        #expect(carb.uuid?.uuidString == id)
        #expect(carb.syncIdentifier == id)
    }
}
