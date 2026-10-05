import Foundation
import Testing
@testable import Libre2Protocol

@Suite struct Libre2ProtocolTests {
    @Test func generatedPacketRoundTripsAndMatchesDriverShape() throws {
        let packet = try Libre2Codec.makePacket(
            glucoseMGDL: 123,
            trend: .rising,
            ageMinutes: 1_234,
            sequence: 0x1234
        )
        #expect(packet.count == 46)
        let plaintext = try Libre2Codec.decrypt(packet: packet)
        #expect(plaintext.count == 44)
        #expect(Libre2Codec.crcIsValid(plaintext))
        #expect(Libre2Codec.age(from: plaintext) == 1_234)
        #expect(Libre2Codec.newestRawGlucose(from: plaintext) == Libre2Codec.rawGlucose(forMGDL: 123))
    }

    @Test func unlockPayloadUsesRepositoryAlgorithmAndValidatesCount() {
        let payload = Libre2Codec.streamingUnlockPayload(unlockCount: 27)
        #expect(payload.count == 12)
        #expect(payload.prefix(4) == Data([69, 0, 0, 0])) // enableTime 42 + count 27
        #expect(Libre2Codec.validateUnlock(payload))

        var damaged = payload
        damaged[11] ^= 0x01
        #expect(!Libre2Codec.validateUnlock(damaged))
    }

    @Test func decryptsLibreTransmitterCapturedVector() throws {
        let uid = Data([0x2F, 0xE7, 0xB1, 0x00, 0x00, 0xA4, 0x07, 0xE0])
        let captured = Data([
            0xB1, 0x94, 0xFA, 0xED, 0x2C, 0xDE, 0xA1, 0x69,
            0x46, 0x57, 0xCF, 0xD0, 0xD8, 0x5A, 0xAA, 0xF1,
            0xE2, 0x89, 0x1C, 0xE9, 0xAC, 0x82, 0x16, 0xFB,
            0x67, 0xA1, 0xD3, 0xB6, 0x3F, 0x91, 0xCD, 0x18,
            0x4B, 0x95, 0x31, 0x6C, 0x04, 0x5F, 0xE1, 0x96,
            0xC4, 0xFD, 0x14, 0xFC, 0x68, 0xE0
        ])
        let plaintext = try Libre2Codec.decrypt(packet: captured, sensorUID: uid)
        #expect(Libre2Codec.crcIsValid(plaintext))
        #expect(Libre2Codec.age(from: plaintext) != nil)
    }

    @Test func allTrendModesProduceValidPackets() throws {
        for trend in Libre2Trend.allCases {
            let packet = try Libre2Codec.makePacket(
                glucoseMGDL: 100,
                trend: trend,
                ageMinutes: 90,
                sequence: 1
            )
            #expect(Libre2Codec.crcIsValid(try Libre2Codec.decrypt(packet: packet)))
        }
    }
}
