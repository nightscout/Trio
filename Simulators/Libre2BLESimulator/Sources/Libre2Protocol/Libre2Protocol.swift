import Foundation

public enum Libre2Profile {
    public static let serviceUUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let writeUUID = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let notifyUUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

    // Stock Trio recognizes names beginning with "miaomiao" without NFC.
    public static let localName = "miaomiao-sim"
    public static let serial = "3MH000GUR5W"
    public static let sensorUID = Data([0xD6, 0xF1, 0x0F, 0x01, 0x00, 0xA4, 0x07, 0xE0])
    public static let patchInfo = Data([0x9D, 0x08, 0x30, 0x01, 0x9C, 0x16])
    public static let enableTime: UInt32 = 42
    public static let maximumAgeMinutes = 14 * 24 * 60

    // Synthetic, deterministic calibration installed by the compatibility patch.
    public static let calibrationI2 = 1
    public static let calibrationI3 = 0.0
    public static let calibrationI4 = 6500.0
    public static let calibrationI6 = 1064.0
    public static let rawTemperature = 1000
    public static let rawTemperatureAdjustment = 0
}

/// Hardware-independent description of the stock MiaoMiao identity and
/// initial control exchange used by LibreTransmitter.
public enum MiaoMiaoCompatibility {
    public static let supportedNamePrefix = "miaomiao"
    public static let requestData = Data([0xF0])
    public static let confirmSensor = Data([0xD3, 0x01])

    public static func stockDriverSupports(peripheralName: String?) -> Bool {
        peripheralName?.lowercased().hasPrefix(supportedNamePrefix) ?? false
    }

    public static func response(to controlWrite: Data) -> MiaoMiaoControlResponse {
        switch controlWrite {
        case confirmSensor:
            return .sensorConfirmed
        case requestData:
            return .sendSensorData
        default:
            return .acceptedUnknown(controlWrite)
        }
    }
}

public enum MiaoMiaoCharacteristicCapability: String, Hashable, Sendable {
    case write
    case writeWithoutResponse
    case notify
}

public enum MiaoMiaoGATTProfile {
    public static let serviceUUID = Libre2Profile.serviceUUID
    public static let writeUUID = Libre2Profile.writeUUID
    public static let notifyUUID = Libre2Profile.notifyUUID
    public static let writeCapabilities: Set<MiaoMiaoCharacteristicCapability> = [
        .write,
        .writeWithoutResponse
    ]
    public static let notifyCapabilities: Set<MiaoMiaoCharacteristicCapability> = [.notify]
}

public enum MiaoMiaoControlResponse: Equatable, Sendable {
    case sensorConfirmed
    case sendSensorData
    case acceptedUnknown(Data)
}

public enum Libre2Trend: String, CaseIterable, Identifiable, Sendable {
    case rapidlyFalling = "↓↓"
    case falling = "↓"
    case stable = "→"
    case rising = "↑"
    case rapidlyRising = "↑↑"

    public var id: String { rawValue }

    /// Approximate mg/dL change per minute, newest relative to older values.
    public var deltaPerMinute: Double {
        switch self {
        case .rapidlyFalling: -3
        case .falling: -1.5
        case .stable: 0
        case .rising: 1.5
        case .rapidlyRising: 3
        }
    }
}

public enum Libre2ProtocolError: Error, Equatable {
    case invalidUID
    case invalidPatchInfo
    case invalidPlaintext
    case invalidPacket
}

public enum Libre2Codec {
    /// Builds the stock MiaoMiao response consumed by Trio's unmodified
    /// MiaoMiaoTransmitter: 18-byte bridge header, 344-byte FRAM, terminator.
    public static func makeMiaoMiaoPacket(
        glucoseMGDL: Double,
        trend: Libre2Trend,
        ageMinutes: Int,
        sensorUID: Data = Libre2Profile.sensorUID
    ) throws -> Data {
        guard sensorUID.count == 8 else { throw Libre2ProtocolError.invalidUID }
        let fram = makeLibreFRAM(
            glucoseMGDL: glucoseMGDL,
            trend: trend,
            ageMinutes: ageMinutes
        )
        var packet = Data(repeating: 0, count: 363)
        packet[0] = 0x28
        packet[1] = 0x01
        packet[2] = 0x6B
        packet[3] = UInt8(truncatingIfNeeded: ageMinutes)
        packet[4] = UInt8(truncatingIfNeeded: ageMinutes >> 8)
        packet.replaceSubrange(5..<13, with: sensorUID)
        packet[13] = 100
        packet[14] = 0x00
        packet[15] = 0x34
        packet[16] = 0x00
        packet[17] = 0x01
        packet.replaceSubrange(18..<362, with: fram)
        packet[362] = 0x29
        return packet
    }

    public static func makeLibreFRAM(
        glucoseMGDL: Double,
        trend: Libre2Trend,
        ageMinutes: Int
    ) -> Data {
        var fram = Data(repeating: 0, count: 344)
        fram[4] = ageMinutes < 60 ? 0x02 : 0x03
        fram[26] = 1 // next trend block
        fram[27] = 1 // next history block

        for index in 0..<16 {
            let value = glucoseMGDL - trend.deltaPerMinute * Double(index)
            writeFRAMMeasurement(into: &fram, offset: 28 + index * 6, glucoseMGDL: value)
        }
        for index in 0..<32 {
            let value = glucoseMGDL - trend.deltaPerMinute * Double((index + 1) * 15)
            writeFRAMMeasurement(into: &fram, offset: 124 + index * 6, glucoseMGDL: value)
        }

        let age = UInt16(clamping: ageMinutes)
        fram[316] = UInt8(truncatingIfNeeded: age)
        fram[317] = UInt8(truncatingIfNeeded: age >> 8)
        let maximumAge = UInt16(Libre2Profile.maximumAgeMinutes)
        fram[326] = UInt8(truncatingIfNeeded: maximumAge)
        fram[327] = UInt8(truncatingIfNeeded: maximumAge >> 8)

        writeBits(into: &fram, byteOffset: 2, bitOffset: 3, bitCount: 10, value: 1)
        writeBits(into: &fram, byteOffset: 336, bitOffset: 8, bitCount: 14, value: 6500)
        writeBits(into: &fram, byteOffset: 336, bitOffset: 52, bitCount: 12, value: 266)

        applyCRC(to: &fram, range: 0..<24)
        applyCRC(to: &fram, range: 24..<320)
        applyCRC(to: &fram, range: 320..<344)
        return fram
    }

    public static func libreFRAMHasValidCRCs(_ fram: Data) -> Bool {
        guard fram.count == 344 else { return false }
        return [0..<24, 24..<320, 320..<344].allSatisfy { range in
            let section = fram.subdata(in: range)
            let enclosed = UInt16(section[0]) << 8 | UInt16(section[1])
            return enclosed == crc16(Array(section.dropFirst(2)), seed: 0xFFFF)
        }
    }

    /// Creates the exact 46-byte encrypted packet consumed by
    /// LibreTransmitter's `Libre2DirectTransmitter`.
    public static func makePacket(
        glucoseMGDL: Double,
        trend: Libre2Trend,
        ageMinutes: Int,
        sequence: UInt16,
        sensorUID: Data = Libre2Profile.sensorUID
    ) throws -> Data {
        guard sensorUID.count >= 6 else { throw Libre2ProtocolError.invalidUID }

        var plaintext = Data(repeating: 0, count: 44)
        for index in 0..<10 {
            let minutesAgo = index < 7 ? Double(index) : Double((index - 6) * 15)
            let historicalGlucose = glucoseMGDL - trend.deltaPerMinute * minutesAgo
            let raw = rawGlucose(forMGDL: historicalGlucose)
            encodeMeasurement(
                into: &plaintext,
                index: index,
                rawGlucose: raw,
                rawTemperature: Libre2Profile.rawTemperature,
                adjustment: Libre2Profile.rawTemperatureAdjustment
            )
        }

        let age = UInt16(clamping: ageMinutes)
        plaintext[40] = UInt8(truncatingIfNeeded: age)
        plaintext[41] = UInt8(truncatingIfNeeded: age >> 8)
        let crc = crc16(Array(plaintext.prefix(42)), seed: 0xFFFF)
        plaintext[42] = UInt8(truncatingIfNeeded: crc >> 8)
        plaintext[43] = UInt8(truncatingIfNeeded: crc)
        return try encrypt(plaintext: plaintext, prefix: sequence, sensorUID: sensorUID)
    }

    public static func encrypt(
        plaintext: Data,
        prefix: UInt16,
        sensorUID: Data = Libre2Profile.sensorUID
    ) throws -> Data {
        guard plaintext.count == 44 else { throw Libre2ProtocolError.invalidPlaintext }
        guard sensorUID.count >= 6 else { throw Libre2ProtocolError.invalidUID }

        let prefixBytes = [UInt8(truncatingIfNeeded: prefix), UInt8(truncatingIfNeeded: prefix >> 8)]
        let d = usefulFunction(uid: sensorUID, x: 0x1B, y: 0x1B6A)
        let x = word(d[1], d[0]) ^ word(d[3], d[2]) | 0x63
        let y = word(prefixBytes[1], prefixBytes[0]) ^ 0x63
        let key = streamKey(uid: sensorUID, x: x, y: y)

        var packet = Data(prefixBytes)
        packet.append(contentsOf: zip(plaintext, key).map(^))
        return packet
    }

    public static func decrypt(
        packet: Data,
        sensorUID: Data = Libre2Profile.sensorUID
    ) throws -> Data {
        guard packet.count == 46 else { throw Libre2ProtocolError.invalidPacket }
        guard sensorUID.count >= 6 else { throw Libre2ProtocolError.invalidUID }
        let d = usefulFunction(uid: sensorUID, x: 0x1B, y: 0x1B6A)
        let x = word(d[1], d[0]) ^ word(d[3], d[2]) | 0x63
        let y = word(packet[1], packet[0]) ^ 0x63
        let key = streamKey(uid: sensorUID, x: x, y: y)
        return Data(zip(packet.dropFirst(2), key).map(^))
    }

    public static func validateUnlock(
        _ payload: Data,
        sensorUID: Data = Libre2Profile.sensorUID,
        patchInfo: Data = Libre2Profile.patchInfo
    ) -> Bool {
        guard payload.count == 12, sensorUID.count >= 6, patchInfo.count >= 6 else { return false }
        let time = UInt32(payload[0])
            | UInt32(payload[1]) << 8
            | UInt32(payload[2]) << 16
            | UInt32(payload[3]) << 24
        guard time >= Libre2Profile.enableTime else { return false }
        let count = UInt16(truncatingIfNeeded: time - Libre2Profile.enableTime)
        return payload == streamingUnlockPayload(
            sensorUID: sensorUID,
            patchInfo: patchInfo,
            unlockCount: count
        )
    }

    public static func streamingUnlockPayload(
        sensorUID: Data = Libre2Profile.sensorUID,
        patchInfo: Data = Libre2Profile.patchInfo,
        unlockCount: UInt16
    ) -> Data {
        precondition(sensorUID.count >= 6 && patchInfo.count >= 6)
        let time = Libre2Profile.enableTime + UInt32(unlockCount)
        let b = [
            UInt8(truncatingIfNeeded: time),
            UInt8(truncatingIfNeeded: time >> 8),
            UInt8(truncatingIfNeeded: time >> 16),
            UInt8(truncatingIfNeeded: time >> 24)
        ]
        let ad = usefulFunction(uid: sensorUID, x: 0x1B, y: 0x1B6A)
        let ed = usefulFunction(
            uid: sensorUID,
            x: 0x1E,
            y: UInt16(truncatingIfNeeded: Libre2Profile.enableTime) ^ word(patchInfo[5], patchInfo[4])
        )
        let t2 = processCrypto([
            word(ed[1], ed[0]) ^ word(b[3], b[2]),
            word(ad[1], ad[0]),
            word(ed[3], ed[2]) ^ word(b[1], b[0]),
            word(ad[3], ad[2])
        ])
        let t4 = processCrypto([
            unlockCRC([0xC1, 0xC4, 0xC3, 0xC0, 0xD4, 0xE1, 0xE7, 0xBA, low(t2[0]), high(t2[0])]).byteSwapped,
            unlockCRC([low(t2[1]), high(t2[1]), low(t2[2]), high(t2[2]), low(t2[3]), high(t2[3])]).byteSwapped,
            unlockCRC(ad + Array(ed.prefix(2))).byteSwapped,
            unlockCRC(Array(ed.suffix(2)) + b).byteSwapped
        ])
        return Data(b + t4.flatMap { [low($0), high($0)] })
    }

    public static func crcIsValid(_ plaintext: Data) -> Bool {
        guard plaintext.count == 44 else { return false }
        let expected = UInt16(plaintext[42]) << 8 | UInt16(plaintext[43])
        return crc16(Array(plaintext.prefix(42)), seed: 0xFFFF) == expected
    }

    public static func age(from plaintext: Data) -> Int? {
        guard plaintext.count == 44 else { return nil }
        return Int(UInt16(plaintext[40]) | UInt16(plaintext[41]) << 8)
    }

    public static func newestRawGlucose(from plaintext: Data) -> Int? {
        guard plaintext.count == 44 else { return nil }
        return Int(plaintext[0]) | (Int(plaintext[1] & 0x3F) << 8)
    }

    public static func rawGlucose(forMGDL glucose: Double) -> Int {
        let temperature = calibratedTemperature(
            rawTemperature: Double(Libre2Profile.rawTemperature),
            adjustment: Double(Libre2Profile.rawTemperatureAdjustment)
        )
        let temperatureFactor = pow(1.045, 32.5 - temperature)
        let table1 = 0.75
        let table2 = 0.0377442
        let raw = (((glucose * table2 + table1) / temperatureFactor)
            * (Libre2Profile.calibrationI4 - Libre2Profile.calibrationI3) / 65.0)
            + Libre2Profile.calibrationI3
        return min(0x3FFF, max(1, Int(raw.rounded())))
    }

    private static func calibratedTemperature(rawTemperature: Double, adjustment: Double) -> Double {
        let resistance = rawTemperature * 72_500 / (adjustment + Libre2Profile.calibrationI6) - 1_000
        let logR = log(resistance)
        let d = pow(logR, 3) * 0.00000005283566
            + pow(logR, 2) * 0.0000007061775
            + logR * 0.0001964561
            + 0.0009180023
        return 1 / d - 273.15
    }

    private static func encodeMeasurement(
        into data: inout Data,
        index: Int,
        rawGlucose: Int,
        rawTemperature: Int,
        adjustment: Int
    ) {
        var value = UInt32(rawGlucose & 0x3FFF)
        value |= UInt32((rawTemperature >> 2) & 0x0FFF) << 14
        value |= UInt32((abs(adjustment) >> 2) & 0x1F) << 26
        if adjustment < 0 { value |= 1 << 31 }
        let offset = index * 4
        for byte in 0..<4 {
            data[offset + byte] = UInt8(truncatingIfNeeded: value >> UInt32(byte * 8))
        }
    }

    private static func writeFRAMMeasurement(
        into data: inout Data,
        offset: Int,
        glucoseMGDL: Double
    ) {
        writeBits(
            into: &data,
            byteOffset: offset,
            bitOffset: 0,
            bitCount: 14,
            value: rawGlucose(forMGDL: glucoseMGDL)
        )
        writeBits(
            into: &data,
            byteOffset: offset,
            bitOffset: 26,
            bitCount: 12,
            value: Libre2Profile.rawTemperature / 4
        )
    }

    private static func writeBits(
        into data: inout Data,
        byteOffset: Int,
        bitOffset: Int,
        bitCount: Int,
        value: Int
    ) {
        for index in 0..<bitCount {
            let absoluteBit = byteOffset * 8 + bitOffset + index
            let byte = absoluteBit / 8
            let bit = absoluteBit % 8
            let mask = UInt8(1 << bit)
            if value & (1 << index) == 0 {
                data[byte] &= ~mask
            } else {
                data[byte] |= mask
            }
        }
    }

    private static func applyCRC(to data: inout Data, range: Range<Int>) {
        let crc = crc16(Array(data[(range.lowerBound + 2)..<range.upperBound]), seed: 0xFFFF)
        data[range.lowerBound] = UInt8(truncatingIfNeeded: crc >> 8)
        data[range.lowerBound + 1] = UInt8(truncatingIfNeeded: crc)
    }

    private static let cryptoKey: [UInt16] = [0xA0C5, 0x6860, 0x0000, 0x14C6]

    private static func streamKey(uid: Data, x: UInt16, y: UInt16) -> [UInt8] {
        var words = processCrypto(prepareVariables(uid: uid, x: x, y: y))
        var key: [UInt8] = []
        for _ in 0..<8 {
            key += words.flatMap { [low($0), high($0)] }
            words = processCrypto(words)
        }
        return key
    }

    private static func usefulFunction(uid: Data, x: UInt16, y: UInt16) -> [UInt8] {
        let block = processCrypto(prepareVariables(uid: uid, x: x, y: y))
        let first = block[0] ^ 0x4163
        let second = block[1] ^ 0x4344
        return [low(first), high(first), low(second), high(second)]
    }

    private static func prepareVariables(uid: Data, x: UInt16, y: UInt16) -> [UInt16] {
        [
            UInt16(truncatingIfNeeded: UInt(word(uid[5], uid[4])) + UInt(x) + UInt(y)),
            UInt16(truncatingIfNeeded: UInt(word(uid[3], uid[2])) + UInt(cryptoKey[2])),
            UInt16(truncatingIfNeeded: UInt(word(uid[1], uid[0])) + UInt(x) * 2),
            0x241A ^ cryptoKey[3]
        ]
    }

    private static func processCrypto(_ input: [UInt16]) -> [UInt16] {
        func op(_ value: UInt16) -> UInt16 {
            var result = value >> 2
            if value & 1 != 0 { result ^= cryptoKey[1] }
            if value & 2 != 0 { result ^= cryptoKey[0] }
            return result
        }
        let r0 = op(input[0]) ^ input[3]
        let r1 = op(r0) ^ input[2]
        let r2 = op(r1) ^ input[1]
        let r3 = op(r2) ^ input[0]
        let r4 = op(r3)
        let r5 = op(r4 ^ r0)
        let r6 = op(r5 ^ r1)
        let r7 = op(r6 ^ r2)
        return [r3 ^ r7, r2 ^ r6, r1 ^ r5, r0 ^ r4]
    }

    private static func crc16(_ bytes: [UInt8], seed: UInt16) -> UInt16 {
        var crc = seed
        for byte in bytes {
            crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt16(byte)) & 0xFF)]
        }
        var reversed: UInt16 = 0
        for _ in 0..<16 {
            reversed = reversed << 1 | crc & 1
            crc >>= 1
        }
        return reversed.byteSwapped
    }

    private static func unlockCRC(_ bytes: [UInt8]) -> UInt16 {
        crc16(bytes, seed: 0xFFFF)
    }

    private static let crcTable: [UInt16] = (0..<256).map { value in
        var crc = UInt16(value)
        for _ in 0..<8 {
            crc = crc & 1 == 1 ? (crc >> 1) ^ 0x8408 : crc >> 1
        }
        return crc
    }

    private static func word(_ high: UInt8, _ low: UInt8) -> UInt16 {
        UInt16(high) << 8 | UInt16(low)
    }

    private static func low(_ value: UInt16) -> UInt8 { UInt8(truncatingIfNeeded: value) }
    private static func high(_ value: UInt16) -> UInt8 { UInt8(truncatingIfNeeded: value >> 8) }
}
