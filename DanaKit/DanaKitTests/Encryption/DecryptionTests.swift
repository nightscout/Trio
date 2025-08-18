@testable import DanaKit
import XCTest

class DecryptionTests: XCTestCase {
    func testDecryptMessage() throws {
        var params = DecryptParam(
            data: Data([165, 165, 14, 234, 243, 192, 163, 190, 134, 184, 225, 185, 222, 197, 183, 222, 197, 31, 241, 90, 90]),
            deviceName: DEVICE_NAME,
            enhancedEncryption: 2,
            isEncryptionMode: true,
            pairingKeyLength: 0,
            randomPairingKeyLength: 0,
            ble5KeyLength: 0,
            timeSecret: Data([]),
            passwordSecret: Data([]),
            passKeySecret: Data([]),
            passKeySecretBackup: Data([])
        )

        let decryptionResult = try decrypt(&params)

        XCTAssertTrue(decryptionResult.isEncryptionMode)
        XCTAssertEqual(decryptionResult.passKeySecret, Data([]))
        XCTAssertEqual(decryptionResult.passKeySecretBackup, Data([]))
        XCTAssertEqual(decryptionResult.passwordSecret, Data([]))
        XCTAssertEqual(decryptionResult.timeSecret, Data([]))
        XCTAssertEqual(decryptionResult.data, Data([2, 0, 79, 75, 77, 9, 80, 18, 54, 54, 54, 56, 54, 54]))
    }

    func testThrowIfLengthDoesNotMatch() {
        var params = DecryptParam(
            data: Data([165, 165, 17, 234, 243, 192, 163, 190, 134, 184, 225, 185, 222, 197, 183, 222, 197, 31, 241, 90, 90]),
            deviceName: DEVICE_NAME,
            enhancedEncryption: 2,
            isEncryptionMode: true,
            pairingKeyLength: 0,
            randomPairingKeyLength: 0,
            ble5KeyLength: 0,
            timeSecret: Data([]),
            passwordSecret: Data([]),
            passKeySecret: Data([]),
            passKeySecretBackup: Data([])
        )

        XCTAssertThrowsError(try decrypt(&params)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "The operation couldn’t be completed. (Package length does not match the length attr. error 0.)"
            )
        }
    }

    func testThrowIfCrcFails() {
        var params = DecryptParam(
            data: Data([165, 165, 14, 234, 243, 192, 163, 190, 134, 184, 225, 185, 222, 197, 183, 222, 197, 31, 21, 90, 90]),
            deviceName: DEVICE_NAME,
            enhancedEncryption: 2,
            isEncryptionMode: true,
            pairingKeyLength: 0,
            randomPairingKeyLength: 0,
            ble5KeyLength: 0,
            timeSecret: Data([]),
            passwordSecret: Data([]),
            passKeySecret: Data([]),
            passKeySecretBackup: Data([])
        )
        XCTAssertThrowsError(try decrypt(&params)) { error in
            XCTAssertEqual(error.localizedDescription, "The operation couldn’t be completed. (Crc checksum failed... error 0.)")
        }
    }
}
