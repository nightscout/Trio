@testable import DanaKit
import XCTest

class CommonUtilsTests: XCTestCase {
    func testEncodePacketSerialNumber() {
        // Pump check command
        var message = Data([165, 165, 12, 1, 0])
        message += DEVICE_NAME.utf8.map { UInt8($0) }
        message += [188, 122, 90, 90]

        let encodedMessage = encodePacketSerialNumber(buffer: &message, deviceName: DEVICE_NAME)

        XCTAssertEqual(
            encodedMessage,
            Data([165, 165, 12, 233, 243, 217, 162, 187, 191, 216, 195, 190, 218, 181, 198, 84, 137, 90, 90])
        )
    }

    // TODO: Validate with older Dana pump
    // func testEncodePacketPassKey() {}

    // TODO: Validate with older Dana pump
    // func testEncodePacketTime() {}

    // TODO: Validate with older Dana pump
    // func testEncodePacketPassKeySerialNumber() {}

    // TODO: Validate with older Dana pump
    // func testEncodePacketPassword() {}

    // TODO: Validate with older Dana pump
    // func testInitialRandomSyncKey() {}

    // TODO: Validate with older Dana pump
    // func testDecryptionRandomSyncKey() {}
}
