import Foundation

/// A glucose record carried in the manufacturer data advertised by Smart/LinX sensors.
struct SmartAdvertisement: Equatable {
    struct GlucoseRecord: Equatable {
        let glucose: UInt16
        let quality: UInt8
        let isValid: Bool
    }

    static let companyIdentifier: UInt16 = 0x0059
    static let payloadLength = 22

    let minutesSinceStart: UInt16
    let status: UInt8
    let calibrationTemperatureStatus: UInt8
    let trend: Int8
    let current: GlucoseRecord
    let previous: [GlucoseRecord]
    let checksum: UInt32

    /// Returns the records carried by one advertisement in chronological order.
    var chronologicalRecords: [(minutesSinceStart: UInt16, record: GlucoseRecord)] {
        var records: [(minutesSinceStart: UInt16, record: GlucoseRecord)] = []
        if minutesSinceStart >= 2, previous.indices.contains(1) {
            records.append((minutesSinceStart - 2, previous[1]))
        }
        if minutesSinceStart >= 1, previous.indices.contains(0) {
            records.append((minutesSinceStart - 1, previous[0]))
        }
        records.append((minutesSinceStart, current))
        return records
    }

    init?(manufacturerData: Data) {
        guard manufacturerData.count >= Self.payloadLength else { return nil }

        // Some Smart/LinX firmware appends transport-specific bytes after the
        // 22-byte payload. They are not covered by the protocol checksum.
        let bytes = [UInt8](manufacturerData.prefix(Self.payloadLength))
        guard Self.uint16(bytes, at: 0) == Self.companyIdentifier else { return nil }

        let checksum = Self.uint32(bytes, at: 18)
        guard checksum == Self.calculateChecksum(bytes) else { return nil }

        minutesSinceStart = Self.uint16(bytes, at: 2)
        status = bytes[4]
        calibrationTemperatureStatus = bytes[5]
        trend = Int8(bitPattern: bytes[6])
        current = Self.glucoseRecord(bytes, wordOffset: 7, qualityOffset: 9)
        previous = [
            Self.glucoseRecord(bytes, wordOffset: 10, qualityOffset: 12),
            Self.glucoseRecord(bytes, wordOffset: 13, qualityOffset: 15)
        ]
        self.checksum = checksum
    }

    private static func glucoseRecord(
        _ bytes: [UInt8],
        wordOffset: Int,
        qualityOffset: Int
    ) -> GlucoseRecord {
        let word = uint16(bytes, at: wordOffset)
        return GlucoseRecord(
            glucose: word & 0x03FF,
            quality: bytes[qualityOffset],
            isValid: word & 0x8000 != 0
        )
    }

    private static func calculateChecksum(_ bytes: [UInt8]) -> UInt32 {
        let payload = Array(bytes[2 ..< 18])
        // The sensor performs this sum in a 32-bit register and discards carry
        // before applying the modulus.
        let sum = stride(from: 0, to: payload.count, by: 4).reduce(UInt32(0)) { partial, offset in
            partial &+ uint32(payload, at: offset)
        }
        var crc = sum % 0x7FA777

        for byte in payload {
            crc ^= UInt32(byte) << 24
            for _ in 0 ..< 8 {
                crc = crc & 0x8000_0000 != 0
                    ? (crc << 1) ^ 0x04C1_1DB7
                    : crc << 1
            }
        }

        return crc
    }

    private static func uint16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) |
            UInt32(bytes[offset + 1]) << 8 |
            UInt32(bytes[offset + 2]) << 16 |
            UInt32(bytes[offset + 3]) << 24
    }
}

/// Suppresses repeated callbacks carrying the same sensor minute and checksum.
struct SmartAdvertisementDeduplicator {
    private var lastForwarded: [UUID: (minute: UInt16, checksum: UInt32)] = [:]

    mutating func shouldForward(
        peripheralIdentifier: UUID,
        advertisement: SmartAdvertisement
    ) -> Bool {
        let fingerprint = (
            minute: advertisement.minutesSinceStart,
            checksum: advertisement.checksum
        )
        if let previous = lastForwarded[peripheralIdentifier],
           previous.minute == fingerprint.minute,
           previous.checksum == fingerprint.checksum
        {
            return false
        }
        lastForwarded[peripheralIdentifier] = fingerprint
        return true
    }
}
