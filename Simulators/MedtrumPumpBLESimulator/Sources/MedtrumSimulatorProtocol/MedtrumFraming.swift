import Foundation

public enum MedtrumCRC8 {
    public static func calculate(_ data: Data) -> UInt8 {
        var crc: UInt8 = 0
        for byte in data {
            crc = table[Int(byte ^ crc)]
        }
        return crc
    }

    private static let table: [UInt8] = (0 ..< 256).map { value in
        var crc = UInt8(value)
        for _ in 0 ..< 8 {
            crc = (crc & 0x80) != 0 ? (crc << 1) ^ 0x9B : crc << 1
        }
        return crc
    }
}

public enum MedtrumFrameError: Error, Equatable {
    case tooShort
    case badCRC
    case inconsistentHeader
    case outOfOrder
    case oversized
}

public struct MedtrumRequestAssembler {
    private var command: UInt8?
    private var sequence: UInt8?
    private var expectedSize = 0
    private var nextFragment: UInt8 = 0
    private var isFragmented = false
    private var payload = Data()

    public init() {}

    public mutating func reset() {
        command = nil
        sequence = nil
        expectedSize = 0
        nextFragment = 0
        isFragmented = false
        payload.removeAll(keepingCapacity: true)
    }

    public mutating func append(_ rawValue: Data) throws -> MedtrumRequest? {
        var frame = rawValue
        guard frame.count >= 5 else { throw MedtrumFrameError.tooShort }

        // Medtrum single-fragment central writes append a zero transport pad after the CRC.
        if frame.count >= 6,
           frame.last == 0,
           MedtrumCRC8.calculate(Data(frame.dropLast(2))) == frame[frame.count - 2]
        {
            frame.removeLast()
        }

        guard MedtrumCRC8.calculate(Data(frame.dropLast())) == frame.last else {
            reset()
            throw MedtrumFrameError.badCRC
        }

        let size = Int(frame[0])
        let incomingCommand = frame[1]
        let incomingSequence = frame[2]
        let fragment = frame[3]
        guard size >= 5, size <= 255 else { throw MedtrumFrameError.oversized }

        if command == nil {
            command = incomingCommand
            sequence = incomingSequence
            expectedSize = size
            isFragmented = fragment != 0
            nextFragment = fragment == 0 ? 0 : 1
        }

        guard command == incomingCommand, sequence == incomingSequence, expectedSize == size else {
            reset()
            throw MedtrumFrameError.inconsistentHeader
        }
        guard fragment == nextFragment else {
            reset()
            throw MedtrumFrameError.outOfOrder
        }

        payload.append(frame[4 ..< frame.count - 1])
        let expectedPayload = expectedSize - 5
        let expectedTransportPayload = expectedPayload + (isFragmented ? 1 : 0)
        guard payload.count <= expectedTransportPayload else {
            reset()
            throw MedtrumFrameError.oversized
        }

        guard payload.count == expectedTransportPayload else {
            nextFragment &+= 1
            return nil
        }

        if isFragmented {
            var logicalCommand = Data([UInt8(expectedSize), incomingCommand, incomingSequence, 0])
            logicalCommand.append(payload.dropLast())
            guard MedtrumCRC8.calculate(logicalCommand) == payload.last else {
                reset()
                throw MedtrumFrameError.badCRC
            }
            payload.removeLast()
        }

        let request = MedtrumRequest(command: incomingCommand, sequence: incomingSequence, payload: payload)
        reset()
        return request
    }
}

public enum MedtrumResponseEncoder {
    /// Responses use 15 logical bytes per ATT value after the repeated four-byte header.
    public static func encode(_ response: MedtrumResponse, maximumUpdateLength: Int = 20) -> [Data] {
        var body = response.responseCode.littleEndianData
        body.append(response.payload)

        let logicalSize = 4 + body.count
        precondition(logicalSize <= 255)

        let capacity = max(1, min(15, maximumUpdateLength - 5))
        let isFragmented = body.count > capacity
        var result: [Data] = []
        var offset = 0
        var fragment: UInt8 = isFragmented ? 1 : 0

        repeat {
            let end = min(offset + capacity, body.count)
            var frame = Data([
                UInt8(logicalSize),
                response.command,
                response.sequence,
                fragment
            ])
            if offset < end {
                frame.append(body[offset ..< end])
            }
            frame.append(MedtrumCRC8.calculate(frame))
            result.append(frame)
            offset = end
            fragment &+= 1
        } while offset < body.count

        return result
    }
}
