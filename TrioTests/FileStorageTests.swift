import Foundation
import Testing

@testable import Trio

@Suite("File Storage Tests", .serialized) struct FileStorageTests {
    let storage = BaseFileStorage()

    struct DummyObject: JSON, Equatable {
        let id: String
        let value: Decimal
    }

    @Test("Can save and retrieve object") func testSaveAndRetrieve() {
        // Given
        let dummy = DummyObject(id: "123", value: 78.2)

        // When
        storage.save(dummy, as: "dummy")
        let retrieved = storage.retrieve("dummy", as: DummyObject.self)

        // Then
        #expect(retrieved == dummy)
    }

    @Test("Can save and retrieve async") func testAsyncSaveAndRetrieve() async {
        // Given
        let dummy = DummyObject(id: "123", value: 78.2)

        // When
        await storage.saveAsync(dummy, as: "dummy_async")
        let retrieved = await storage.retrieveAsync("dummy_async", as: DummyObject.self)

        // Then
        #expect(retrieved == dummy)
    }

    @Test("Can append single value") func testAppendSingleValue() {
        // Given
        let dummy1 = DummyObject(id: "1", value: 10.0)
        let dummy2 = DummyObject(id: "2", value: 20.0)

        // When
        storage.save([dummy1], as: "dummies")
        storage.append(dummy2, to: "dummies")

        // Then
        let retrieved = storage.retrieve("dummies", as: [DummyObject].self)
        #expect(retrieved?.count == 2)
        #expect(retrieved?.contains(dummy1) == true)
        #expect(retrieved?.contains(dummy2) == true)
    }

    @Test("Can append multiple values") func testAppendMultipleValues() {
        // Given
        let dummy1 = DummyObject(id: "1", value: 10.0)
        let newDummies = [
            DummyObject(id: "2", value: 20.0),
            DummyObject(id: "3", value: 30.0)
        ]

        // When
        storage.save([dummy1], as: "dummies_multiple")
        storage.append(newDummies, to: "dummies_multiple")

        // Then
        let retrieved = storage.retrieve("dummies_multiple", as: [DummyObject].self)
        #expect(retrieved?.count == 3)
    }

    @Test("Can append unique values by key path") func testAppendUniqueByKeyPath() {
        // Given
        let dummy1 = DummyObject(id: "1", value: 10.0)
        let dummy2 = DummyObject(id: "1", value: 20.0) // Same id

        // When
        storage.save([dummy1], as: "unique_dummies")
        storage.append(dummy2, to: "unique_dummies", uniqBy: \.id)

        // Then
        let retrieved = storage.retrieve("unique_dummies", as: [DummyObject].self)
        #expect(retrieved?.count == 1, "Should not append duplicate id")
    }

    @Test("Can remove file") func testRemoveFile() {
        // Given
        let dummy = DummyObject(id: "123", value: 78.2)
        storage.save(dummy, as: "to_delete")

        // When
        storage.remove("to_delete")

        // Then
        let retrieved = storage.retrieve("to_delete", as: DummyObject.self)
        #expect(retrieved == nil)
    }

    @Test("Can rename file") func testRenameFile() {
        // Given
        let dummy = DummyObject(id: "123", value: 78.2)
        storage.save(dummy, as: "old_name")

        // When
        storage.rename("old_name", to: "new_name")

        // Then
        let oldRetrieved = storage.retrieve("old_name", as: DummyObject.self)
        let newRetrieved = storage.retrieve("new_name", as: DummyObject.self)

        #expect(newRetrieved == dummy)
    }

    @Test("Can execute transaction") func testTransaction() {
        // Given
        let dummy = DummyObject(id: "123", value: 78.2)

        // When
        storage.transaction { storage in
            storage.save(dummy, as: "transaction_test")
        }

        // Then
        let retrieved = storage.retrieve("transaction_test", as: DummyObject.self)
        #expect(retrieved == dummy)
    }

    @Test("Can parse mmol/L settings to mg/dL") func testParseSettingsToMgdL() {
        // Given
        var preferences = Preferences()
        preferences.threshold_setting = 5.5 // mmol/L
        storage.save(preferences, as: OpenAPS.Settings.preferences)

        // When
        let wasParsed = storage.parseOnFileSettingsToMgdL()

        // Then
        #expect(wasParsed == true)
        let parsed = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)
        #expect(parsed?.threshold_setting == 100) // default mg/dL value
    }
}
