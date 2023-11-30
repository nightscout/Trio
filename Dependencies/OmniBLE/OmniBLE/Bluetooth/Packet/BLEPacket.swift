//
//  BLEPacket.swift
//  OmniBLE
//
//  Created by Randall Knutson on 8/11/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
let MAX_SIZE = 20

protocol BlePacket {
    var payload: Data { get }
    
    func toData() -> Data
}

struct FirstBlePacket: BlePacket {
    private static let HEADER_SIZE_WITHOUT_MIDDLE_PACKETS = 7 // we are using all fields
    private static let HEADER_SIZE_WITH_MIDDLE_PACKETS = 2

    internal static let CAPACITY_WITHOUT_MIDDLE_PACKETS =
        MAX_SIZE - HEADER_SIZE_WITHOUT_MIDDLE_PACKETS // we are using all fields
    internal static let CAPACITY_WITH_MIDDLE_PACKETS =
        MAX_SIZE - HEADER_SIZE_WITH_MIDDLE_PACKETS // we are not using crc32 or size
    internal static let CAPACITY_WITH_THE_OPTIONAL_PLUS_ONE_PACKET = 18

    private static let MAX_FRAGMENTS = 15 // 15*20=300 bytes

    let fullFragments: Int
    let payload: Data
    var size: UInt8?
    var crc32: Data?
    var oneExtraPacket: Bool = false

    func toData() -> Data {
        var bb = Data(capacity: MAX_SIZE)
        bb.append(UInt8(0)) // index
        bb.append(UInt8(fullFragments)) // # of fragments except FirstBlePacket and LastOptionalPlusOneBlePacket
        
        if let crc32 = crc32 {
            bb.append(crc32)
        }
        if let size = size {
            bb.append(UInt8(size))
        }
        bb.append(payload)

        return bb;
    }
    
    static func parse(payload: Data) throws -> FirstBlePacket {
        guard payload.count >= HEADER_SIZE_WITH_MIDDLE_PACKETS else {
            throw PodProtocolError.messageIOException("Wrong packet size")
        }

        if (Int(payload[0]) != 0) {
            // most likely we lost the first packet.
            throw PodProtocolError.incorrectPacketException(payload, 0)
        }

        let fullFragments = Int(payload[1])
        guard (fullFragments <= MAX_FRAGMENTS) else {
            throw PodProtocolError.messageIOException(String(format: "Received more than %d fragments", MAX_FRAGMENTS))
        }
        guard (fullFragments > 0) else {
            throw PodProtocolError.messageIOException("Invalid message with 0 fragments")
        }

        guard payload.count >= HEADER_SIZE_WITHOUT_MIDDLE_PACKETS else {
            throw PodProtocolError.messageIOException("Wrong packet size")
        }

        if (fullFragments == 0) {
            let rest = payload[6]
            let end = min(Int(rest) + HEADER_SIZE_WITHOUT_MIDDLE_PACKETS, payload.count)
            guard payload.count >= end else {
                throw PodProtocolError.messageIOException("Wrong packet size")
            }

            return FirstBlePacket(
                fullFragments: fullFragments,
                payload: payload.subdata(in: HEADER_SIZE_WITHOUT_MIDDLE_PACKETS..<end),
                size:  rest,
                crc32: payload.subdata(in: 2..<6),
                oneExtraPacket:  Int(rest) + HEADER_SIZE_WITHOUT_MIDDLE_PACKETS > end
            )
        }
        else if (payload.count < MAX_SIZE) {
            throw PodProtocolError.incorrectPacketException(payload, 0)
        }
        else {
            return FirstBlePacket(
                fullFragments: fullFragments,
                payload: payload.subdata(in: HEADER_SIZE_WITH_MIDDLE_PACKETS..<MAX_SIZE)
            )
        }
    }
}

struct MiddleBlePacket: BlePacket {
    internal static let CAPACITY = 19
    let index: UInt8
    let payload: Data
        
    func toData() -> Data {
        return Data([index]) + payload
    }
    
    static func parse(payload: Data) throws -> MiddleBlePacket {
        guard payload.count >= MAX_SIZE else { throw PodProtocolError.messageIOException("Wrong packet size") }
        return MiddleBlePacket(
            index: payload[0],
            payload: payload.subdata(in: 1..<MAX_SIZE)
        )
    }
}

struct LastBlePacket: BlePacket {
    static let HEADER_SIZE = 6
    internal static let CAPACITY = MAX_SIZE - HEADER_SIZE

    let index: UInt8
    let size: UInt8
    let payload: Data
    let crc32: Data
    var oneExtraPacket: Bool = false

    func toData() -> Data {
        var bb = Data(capacity: MAX_SIZE)
        bb.append(index)
        bb.append(size)
        bb.append(crc32)
        bb.append(payload)
        bb.append(Data(count: MAX_SIZE - payload.count - LastBlePacket.HEADER_SIZE))
        return bb
    }
    
    static func parse(payload: Data) throws -> LastBlePacket {
        guard payload.count >= LastBlePacket.HEADER_SIZE else { throw PodProtocolError.messageIOException("Wrong packet size") }

        let rest = payload[1]
        let end = min(Int(rest) + LastBlePacket.HEADER_SIZE, payload.count)

        guard payload.count >= end else { throw PodProtocolError.messageIOException("Wrong packet size") }

        return LastBlePacket(
            index: payload[0],
            size: rest,
            payload: payload.subdata(in: LastBlePacket.HEADER_SIZE..<end),
            crc32: payload.subdata(in: 2..<6),
            oneExtraPacket: Int(rest) + LastBlePacket.HEADER_SIZE > end
        )
    }
}

struct LastOptionalPlusOneBlePacket: BlePacket {
    static let HEADER_SIZE = 2
    let index: UInt8
    let payload: Data
    let size: UInt8

    func toData() -> Data {
        return Data([index, size]) + payload + Data(count: MAX_SIZE - payload.count - 2)
    }

    static func parse(payload: Data) throws -> LastOptionalPlusOneBlePacket {
        guard payload.count >= 2 else { throw PodProtocolError.messageIOException("Wrong packet size") }
        let size = payload[1]
        guard payload.count >= HEADER_SIZE + Int(size) else { throw PodProtocolError.messageIOException("Wrong packet size") }

        return LastOptionalPlusOneBlePacket(
            index: payload[0],
            payload: payload.subdata(in: HEADER_SIZE..<HEADER_SIZE + Int(size)),
            size: size
        )
    }
}
