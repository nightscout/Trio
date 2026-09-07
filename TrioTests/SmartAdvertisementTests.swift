import Foundation
import Testing
@testable import Trio

@Suite("Smart Advertisement Tests") struct SmartAdvertisementTests {
    // These fixtures are synthetic protocol vectors. They do not contain
    // production sensor identifiers, timestamps, or health data.
    private let validPayload = "5900D2040000FE7B805F7A805E79805D0000858BCA5B"
    private let overflowPayload = "5900FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF938CC73A"

    @Test("Parses a valid synthetic Smart advertisement") func parsesAdvertisement() throws {
        let advertisement = try #require(
            SmartAdvertisement(manufacturerData: try data(from: validPayload))
        )

        #expect(advertisement.minutesSinceStart == 1234)
        #expect(advertisement.status == 0)
        #expect(advertisement.calibrationTemperatureStatus == 0)
        #expect(advertisement.trend == -2)
        #expect(advertisement.current == .init(glucose: 123, quality: 95, isValid: true))
        #expect(advertisement.previous == [
            .init(glucose: 122, quality: 94, isValid: true),
            .init(glucose: 121, quality: 93, isValid: true)
        ])
    }

    @Test("Rejects an invalid checksum") func rejectsInvalidChecksum() throws {
        var bytes = [UInt8](try data(from: validPayload))
        bytes[7] ^= 0x01
        #expect(SmartAdvertisement(manufacturerData: Data(bytes)) == nil)
    }

    @Test("Rejects another manufacturer") func rejectsAnotherManufacturer() throws {
        var bytes = [UInt8](try data(from: validPayload))
        bytes[0] = 0x58
        #expect(SmartAdvertisement(manufacturerData: Data(bytes)) == nil)
    }

    @Test("Rejects incomplete advertisements") func rejectsIncompleteAdvertisement() throws {
        let bytes = try data(from: validPayload)
        #expect(SmartAdvertisement(manufacturerData: bytes.dropLast()) == nil)
    }

    @Test("Ignores trailing transport data") func acceptsTrailingTransportData() throws {
        var bytes = try data(from: validPayload)
        bytes.append(contentsOf: [0x01, 0x02, 0x03, 0x04, 0x05])
        #expect(SmartAdvertisement(manufacturerData: bytes)?.minutesSinceStart == 1234)
    }

    @Test("Handles checksum sum overflow") func handlesChecksumOverflow() throws {
        let advertisement = try #require(
            SmartAdvertisement(manufacturerData: try data(from: overflowPayload))
        )
        #expect(advertisement.checksum == 0x3AC7_8C93)
    }

    @Test("Orders current and previous records chronologically") func ordersRecords() throws {
        let advertisement = try #require(
            SmartAdvertisement(manufacturerData: try data(from: validPayload))
        )

        #expect(advertisement.chronologicalRecords.map(\.minutesSinceStart) == [1232, 1233, 1234])
        #expect(advertisement.chronologicalRecords.map(\.record.glucose) == [121, 122, 123])
    }

    @Test("Suppresses only repeated advertisements from the same peripheral") func suppressesDuplicates() throws {
        let advertisement = try #require(
            SmartAdvertisement(manufacturerData: try data(from: validPayload))
        )
        let firstPeripheral = UUID()
        let secondPeripheral = UUID()
        var deduplicator = SmartAdvertisementDeduplicator()

        let firstResult = deduplicator.shouldForward(
            peripheralIdentifier: firstPeripheral,
            advertisement: advertisement
        )
        let repeatedResult = deduplicator.shouldForward(
            peripheralIdentifier: firstPeripheral,
            advertisement: advertisement
        )
        let secondPeripheralResult = deduplicator.shouldForward(
            peripheralIdentifier: secondPeripheral,
            advertisement: advertisement
        )

        #expect(firstResult)
        #expect(!repeatedResult)
        #expect(secondPeripheralResult)
    }

    private func data(from hex: String) throws -> Data {
        let characters = Array(hex)
        guard characters.count.isMultiple(of: 2) else {
            throw TestError("Hex input must contain an even number of characters")
        }

        return try Data(stride(from: 0, to: characters.count, by: 2).map { offset in
            let byte = String(characters[offset ... offset + 1])
            guard let value = UInt8(byte, radix: 16) else {
                throw TestError("Invalid hexadecimal byte: \(byte)")
            }
            return value
        })
    }
}
