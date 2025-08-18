@testable import DanaKit
import XCTest

class EncryptionTests: XCTestCase {
    func testEncodePumpCheckCommand() {
        let param = EncryptParams(
            operationCode: DanaPacketType.OPCODE_ENCRYPTION__PUMP_CHECK,
            data: nil,
            deviceName: DEVICE_NAME,
            enhancedEncryption: 0,
            timeSecret: Data(),
            passwordSecret: Data(),
            passKeySecret: Data()
        )
        let result = encrypt(param)
        XCTAssertTrue(result.isEncryptionMode)
        XCTAssertEqual(
            result.data,
            Data([165, 165, 12, 233, 243, 217, 162, 187, 191, 216, 195, 190, 218, 181, 198, 84, 137, 90, 90])
        )
    }

    func testEncodeTimeInformationCommand() {
        let param = EncryptParams(
            operationCode: DanaPacketType.OPCODE_ENCRYPTION__TIME_INFORMATION,
            data: Data([0, 0, 0, 0]),
            deviceName: DEVICE_NAME,
            enhancedEncryption: 0,
            timeSecret: Data(),
            passwordSecret: Data(),
            passKeySecret: Data()
        )
        let result = encrypt(param)
        XCTAssertTrue(result.isEncryptionMode)
        XCTAssertEqual(result.data, Data([165, 165, 6, 233, 242, 143, 232, 243, 143, 247, 28, 90, 90]))
    }

    func testEncodeTimeInformationCommandEnhancedEncryption2() {
        let param = EncryptParams(
            operationCode: DanaPacketType.OPCODE_ENCRYPTION__TIME_INFORMATION,
            data: Data([0, 0, 0, 0]),
            deviceName: DEVICE_NAME,
            enhancedEncryption: 2,
            timeSecret: Data(),
            passwordSecret: Data(),
            passKeySecret: Data()
        )
        let result = encrypt(param)
        XCTAssertTrue(result.isEncryptionMode)
        XCTAssertEqual(result.data, Data([165, 165, 6, 233, 242, 143, 229, 226, 137, 183, 82, 90, 90]))
    }

    func testEncodeTimeInformationCommandEmpty() {
        let param = EncryptParams(
            operationCode: DanaPacketType.OPCODE_ENCRYPTION__TIME_INFORMATION,
            data: Data(),
            deviceName: DEVICE_NAME,
            enhancedEncryption: 0,
            timeSecret: Data(),
            passwordSecret: Data(),
            passKeySecret: Data()
        )
        let result = encrypt(param)
        XCTAssertTrue(result.isEncryptionMode)
        XCTAssertEqual(result.data, Data([165, 165, 2, 233, 242, 134, 120, 90, 90]))
    }

    func testEncodeGetPumpCheckCommand() {
        let param = EncryptParams(
            operationCode: DanaPacketType.OPCODE_ENCRYPTION__GET_PUMP_CHECK,
            data: Data(),
            deviceName: DEVICE_NAME,
            enhancedEncryption: 0,
            timeSecret: Data(),
            passwordSecret: Data(),
            passKeySecret: Data()
        )
        let result = encrypt(param)
        XCTAssertTrue(result.isEncryptionMode)
        XCTAssertEqual(result.data, Data([165, 165, 2, 233, 0, 81, 109, 90, 90]))
    }

    func testEncodeGetEasyMenuCheckCommand() {
        let param = EncryptParams(
            operationCode: DanaPacketType.OPCODE_ENCRYPTION__GET_EASYMENU_CHECK,
            data: Data(),
            deviceName: DEVICE_NAME,
            enhancedEncryption: 0,
            timeSecret: Data(),
            passwordSecret: Data(),
            passKeySecret: Data()
        )
        let result = encrypt(param)
        XCTAssertTrue(result.isEncryptionMode)
        XCTAssertEqual(result.data, Data([165, 165, 2, 233, 7, 33, 82, 90, 90]))
    }

    func testEncodePasskeyRequestCommand() {
        let param = EncryptParams(
            operationCode: DanaPacketType.OPCODE_ENCRYPTION__PASSKEY_REQUEST,
            data: Data(),
            deviceName: DEVICE_NAME,
            enhancedEncryption: 0,
            timeSecret: Data(),
            passwordSecret: Data(),
            passKeySecret: Data()
        )
        let result = encrypt(param)
        XCTAssertTrue(result.isEncryptionMode)
        XCTAssertEqual(result.data, Data([165, 165, 2, 233, 34, 80, 77, 90, 90]))
    }

    func testEncodeCheckPasskeyCommand() {
        let param = EncryptParams(
            operationCode: DanaPacketType.OPCODE_ENCRYPTION__CHECK_PASSKEY,
            data: Data([1, 2]),
            deviceName: DEVICE_NAME,
            enhancedEncryption: 0,
            timeSecret: Data(),
            passwordSecret: Data(),
            passKeySecret: Data()
        )
        let result = encrypt(param)
        XCTAssertTrue(result.isEncryptionMode)
        XCTAssertEqual(result.data, Data([165, 165, 4, 233, 35, 228, 128, 28, 180, 90, 90]))
    }

    func testEncodeNormalCommandEnhancedEncryption2() {
        let param = EncryptParams(
            operationCode: DanaPacketType.OPCODE_BASAL__SET_TEMPORARY_BASAL,
            data: Data([200, 1]),
            deviceName: DEVICE_NAME,
            enhancedEncryption: 2,
            timeSecret: Data(),
            passwordSecret: Data(),
            passKeySecret: Data()
        )
        let result = encrypt(param)
        XCTAssertFalse(result.isEncryptionMode)
        XCTAssertEqual(result.data, Data([165, 165, 4, 73, 147, 71, 233, 137, 149, 90, 90]))
    }

    func testEncodeNormalCommandEmptyDataEnhancedEncryption2() {
        let param = EncryptParams(
            operationCode: DanaPacketType.OPCODE_REVIEW__INITIAL_SCREEN_INFORMATION,
            data: Data(),
            deviceName: DEVICE_NAME,
            enhancedEncryption: 2,
            timeSecret: Data(),
            passwordSecret: Data(),
            passKeySecret: Data()
        )
        let result = encrypt(param)
        XCTAssertFalse(result.isEncryptionMode)
        XCTAssertEqual(result.data, Data([165, 165, 2, 73, 241, 235, 35, 90, 90]))
    }

    // TODO: Need example keys from older Dana pumps
    // func testEncodeNormalCommandEmptyDataEnhancedEncryption0() {}

    func testEncodeNormalCommandEmptyDataEnhancedEncryption1() {
        // DANA_PACKET_TYPE.ETC__KEEP_CONNECTION
        let data = Data([165, 165, 2, 65, 9, 176, 75, 90, 90])
        let enhancedEncryption: UInt8 = 1
        let pairingKey = Data([237, 241, 117, 95, 135, 61])
        let randomPairingKey = Data([181, 201, 65])

        let randomSyncKey = initialRandomSyncKey(pairingKey: pairingKey)

        var params = EncryptSecondLevelParams(
            buffer: data,
            enhancedEncryption: enhancedEncryption,
            pairingKey: pairingKey,
            randomPairingKey: randomPairingKey,
            randomSyncKey: randomSyncKey,
            bleRandomKeys: Ble5Keys
        )
        let result = encryptSecondLevel(&params)

        XCTAssertEqual(result.randomSyncKey, 207)
        XCTAssertEqual(result.buffer, Data([19, 203, 1, 47, 8, 203, 194, 168, 207]))
    }

    func testEncodeNormalCommandEmptyDataEnhancedEncryption1MultipleMessages() {
        // DANA_PACKET_TYPE.ETC__KEEP_CONNECTION
        let dataKeepConnection = Data([165, 165, 2, 65, 9, 176, 75, 90, 90])
        let enhancedEncryption: UInt8 = 1
        let pairingKey = Data([237, 241, 117, 95, 135, 61])
        let randomPairingKey = Data([181, 201, 65])

        var randomSyncKey = initialRandomSyncKey(pairingKey: pairingKey)

        var paramsKeepConnection = EncryptSecondLevelParams(
            buffer: dataKeepConnection,
            enhancedEncryption: enhancedEncryption,
            pairingKey: pairingKey,
            randomPairingKey: randomPairingKey,
            randomSyncKey: randomSyncKey,
            bleRandomKeys: Ble5Keys
        )
        let resultKeepConnection = encryptSecondLevel(&paramsKeepConnection)

        XCTAssertEqual(resultKeepConnection.randomSyncKey, 207)
        XCTAssertEqual(resultKeepConnection.buffer, Data([19, 203, 1, 47, 8, 203, 194, 168, 207]))

        randomSyncKey = resultKeepConnection.randomSyncKey

        // Decrypt ETC__KEEP_CONNECTION
        let decryptKeepConnection = Data([83, 143, 118, 179, 100, 46, 5, 39, 50, 225])

        var paramsDecryptKeepConnection = DecryptSecondLevelParams(
            buffer: decryptKeepConnection,
            enhancedEncryption: enhancedEncryption,
            pairingKey: pairingKey,
            randomPairingKey: randomPairingKey,
            randomSyncKey: randomSyncKey,
            bleRandomKeys: Ble5Keys
        )
        let resultDecryptKeepConnection = decryptSecondLevel(&paramsDecryptKeepConnection)

        XCTAssertEqual(resultDecryptKeepConnection.randomSyncKey, 225)
        XCTAssertEqual(resultDecryptKeepConnection.buffer, Data([165, 165, 3, 82, 9, 136, 174, 2, 90, 90]))

        randomSyncKey = resultDecryptKeepConnection.randomSyncKey

        // DANA_PACKET_TYPE.REVIEW__GET_SHIPPING_INFORMATION
        let dataGetShippingInformation = Data([165, 165, 2, 65, 214, 138, 205, 90, 90])

        var paramsGetShippingInformation = EncryptSecondLevelParams(
            buffer: dataGetShippingInformation,
            enhancedEncryption: enhancedEncryption,
            pairingKey: pairingKey,
            randomPairingKey: randomPairingKey,
            randomSyncKey: randomSyncKey,
            bleRandomKeys: Ble5Keys
        )
        let resultGetShippingInformation = encryptSecondLevel(&paramsGetShippingInformation)

        XCTAssertEqual(resultGetShippingInformation.randomSyncKey, 177)
        XCTAssertEqual(resultGetShippingInformation.buffer, Data([70, 81, 52, 121, 145, 240, 177, 76, 177]))
    }

    func testEncodeSecondLevel() {
        // DANA_PACKET_TYPE.OPCODE_REVIEW__INITIAL_SCREEN_INFORMATION
        let data = Data([165, 165, 2, 73, 241, 235, 35, 90, 90])
        let enhancedEncryption: UInt8 = 2
        let emptyKey = Data([])

        var params = EncryptSecondLevelParams(
            buffer: data,
            enhancedEncryption: enhancedEncryption,
            pairingKey: emptyKey,
            randomPairingKey: emptyKey,
            randomSyncKey: 0,
            bleRandomKeys: Ble5Keys
        )
        let result = encryptSecondLevel(&params)

        XCTAssertEqual(result.randomSyncKey, 0)
        XCTAssertEqual(result.buffer, Data([126, 126, 235, 16, 154, 122, 245, 170, 170]))
    }
}
