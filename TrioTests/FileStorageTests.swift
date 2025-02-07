@testable import Trio
import XCTest

class FileStorageTests: XCTestCase {
    let fileStorage = BaseFileStorage()

    struct DummyObject: JSON, Equatable {
        let id: String
        let value: Decimal
    }

    func testFileStorageTrio() {
        let dummyObject = DummyObject(id: "21342Z", value: 78.2)
        fileStorage.save(dummyObject, as: "dummyObject")
        let dummyObjectRetrieve = fileStorage.retrieve("dummyObject", as: DummyObject.self)
        XCTAssertTrue(dummyObject == dummyObjectRetrieve)
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
}
