import Foundation
import Testing
@testable import Libre2Protocol

@Suite struct Libre2ProtocolTests {
    @Test func simulatorIdentityPassesStockDriverClassification() {
        #expect(Libre2Profile.localName == "miaomiao")
        #expect(Libre2Profile.localName.utf8.count == 8)
        #expect(MiaoMiaoCompatibility.stockDriverSupports(peripheralName: Libre2Profile.localName))
        #expect(MiaoMiaoCompatibility.stockDriverSupports(peripheralName: "MiaoMiao"))
        #expect(!MiaoMiaoCompatibility.stockDriverSupports(peripheralName: "Libre2BLESimulator"))
        #expect(!MiaoMiaoCompatibility.stockDriverSupports(peripheralName: nil))
    }

    @Test func simulatorAdvertisementProducesVisibleStockSelectorRow() {
        #expect(
            MiaoMiaoCompatibility.stockThirdPartySelectorDisposition(
                peripheralName: Libre2Profile.localName
            ) == .visibleRow
        )

        // This is the exact screenshot failure mode: the old direct simulator
        // identity is counted as supported, but DeviceItem hides its row.
        #expect(
            MiaoMiaoCompatibility.stockThirdPartySelectorDisposition(
                peripheralName: "ABBOTTTRIOSIM01"
            ) == .hiddenRequiresSetup
        )
    }

    @Test func gattProfileMatchesStockMiaoMiaoNordicUART() {
        #expect(MiaoMiaoGATTProfile.serviceUUID == "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        #expect(MiaoMiaoGATTProfile.writeUUID == "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
        #expect(MiaoMiaoGATTProfile.notifyUUID == "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
        #expect(MiaoMiaoGATTProfile.writeCapabilities == [.write, .writeWithoutResponse])
        #expect(MiaoMiaoGATTProfile.notifyCapabilities == [.notify])
    }

    @Test func stockInitialExchangeConfirmsThenRequestsData() {
        #expect(MiaoMiaoCompatibility.response(to: Data([0xD3, 0x01])) == .sensorConfirmed)
        #expect(MiaoMiaoCompatibility.response(to: Data([0xF0])) == .sendSensorData)
        #expect(
            MiaoMiaoCompatibility.response(to: Data([0xD1, 0x05]))
                == .acceptedUnknown(Data([0xD1, 0x05]))
        )
    }

    @Test func stockMiaoMiaoPacketContainsValidSyntheticFRAM() throws {
        let packet = try Libre2Codec.makeMiaoMiaoPacket(
            glucoseMGDL: 123,
            trend: .rising,
            ageMinutes: 90
        )
        #expect(packet.count == 363)
        #expect(packet.first == 0x28)
        #expect(packet.last == 0x29)
        #expect(packet.subdata(in: 5..<13) == Libre2Profile.sensorUID)

        let fram = packet.subdata(in: 18..<362)
        #expect(Libre2Codec.libreFRAMHasValidCRCs(fram))
        #expect(fram[4] == 0x03)
        #expect(fram[26] == 1)
        #expect(fram[27] == 1)
        #expect(Int(fram[316]) | Int(fram[317]) << 8 == 90)
        #expect(Int(fram[326]) | Int(fram[327]) << 8 == Libre2Profile.maximumAgeMinutes)
        let newestRaw = Int(fram[28]) | Int(fram[29] & 0x3F) << 8
        #expect(newestRaw == Libre2Codec.rawGlucose(forMGDL: 123))
    }

    @Test func stockBridgeMarksWarmupAndReadyStates() {
        #expect(Libre2Codec.makeLibreFRAM(glucoseMGDL: 100, trend: .stable, ageMinutes: 59)[4] == 0x02)
        #expect(Libre2Codec.makeLibreFRAM(glucoseMGDL: 100, trend: .stable, ageMinutes: 60)[4] == 0x03)
    }

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
