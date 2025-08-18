@testable import DanaKit
import XCTest

class CRCTests: XCTestCase {
    func testGenerateCrcEnhancedEncryption0IsEncryptionCommandTrue() {
        // pump_check command
        let data: [UInt8] = [1, 0] + Array(DEVICE_NAME.utf8)
        let crc = generateCrc(buffer: Data(data), enhancedEncryption: 0, isEncryptionCommand: true)

        XCTAssertEqual(crc, 0xBC7A)
    }

    func testGenerateCrcEnhancedEncryption1IsEncryptionCommandFalse() {
        // BasalSetTemporary command (200%, 1 hour)
        let data: [UInt8] = [161, 96, 200, 1]
        let crc = generateCrc(buffer: Data(data), enhancedEncryption: 1, isEncryptionCommand: false)

        XCTAssertEqual(crc, 0x33FD)
    }

    func testGenerateCrcEnhancedEncryption1IsEncryptionCommandTrue() {
        // TIME_INFORMATION command -> sendTimeInfo
        let data: [UInt8] = [1, 1]
        let crc = generateCrc(buffer: Data(data), enhancedEncryption: 1, isEncryptionCommand: true)

        XCTAssertEqual(crc, 0x0990)
    }

    func testGenerateCrcEnhancedEncryption2IsEncryptionCommandFalse() {
        // BasalSetTemporary command (200%, 1 hour)
        let data: [UInt8] = [161, 96, 200, 1]
        let crc = generateCrc(buffer: Data(data), enhancedEncryption: 2, isEncryptionCommand: false)

        XCTAssertEqual(crc, 0x7A1A)
    }

    func testGenerateCrcEnhancedEncryption2IsEncryptionCommandTrue() {
        // TIME_INFORMATION command -> sendBLE5PairingInformation
        let data: [UInt8] = [1, 1, 0, 0, 0, 0]
        let crc = generateCrc(buffer: Data(data), enhancedEncryption: 2, isEncryptionCommand: true)

        XCTAssertEqual(crc, 0x1FEF)
    }
}
