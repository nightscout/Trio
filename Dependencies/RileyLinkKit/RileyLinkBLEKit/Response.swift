//
//  Response.swift
//  RileyLinkBLEKit
//
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

enum ResponseCode: UInt8 {
    case rxTimeout          = 0xaa
    case commandInterrupted = 0xbb
    case zeroData           = 0xcc
    case success            = 0xdd
    case invalidParam       = 0x11
    case unknownCommand     = 0x22
}

protocol Response {
    var code: ResponseCode { get }

    init?(data: Data)

    init?(legacyData data: Data)
}

struct CodeResponse: Response {
    let code: ResponseCode

    init?(data: Data) {
        guard data.count == 1, let code = ResponseCode(rawValue: data[data.startIndex]) else {
            return nil
        }

        self.code = code
    }

    init?(legacyData data: Data) {
        guard data.count == 0 else {
            return nil
        }

        self.code = .success
    }
}

struct ReadRegisterResponse: Response {
    let code: ResponseCode
    let value: UInt8
    
    init?(data: Data) {
        guard data.count > 1, let code = ResponseCode(rawValue: data[data.startIndex]) else {
            return nil
        }
        
        self.init(code: code, value: data[data.startIndex.advanced(by: 1)])
    }
    
    init?(legacyData data: Data) {
        self.init(code: .success, value: data[0])
    }
    
    private init?(code: ResponseCode, value: UInt8) {
        self.code = code
        self.value = value
    }
}

struct UpdateRegisterResponse: Response {
    let code: ResponseCode

    init?(data: Data) {
        guard data.count > 0, let code = ResponseCode(rawValue: data[data.startIndex]) else {
            return nil
        }

        self.code = code
    }

    private enum LegacyCode: UInt8 {
        case success = 1
        case invalidRegister = 2

        var responseCode: ResponseCode {
            switch self {
            case .success:
                return .success
            case .invalidRegister:
                return .invalidParam
            }
        }
    }

    init?(legacyData data: Data) {
        guard data.count > 0, let code = LegacyCode(rawValue: data[data.startIndex])?.responseCode else {
            return nil
        }

        self.code = code
    }
}

struct GetVersionResponse: Response {
    let code: ResponseCode
    let version: String

    init?(data: Data) {
        guard data.count > 1, let code = ResponseCode(rawValue: data[data.startIndex]) else {
            return nil
        }

        self.init(code: code, versionData: data[data.startIndex.advanced(by: 1)...])
    }

    init?(legacyData data: Data) {
        self.init(code: .success, versionData: data)
    }

    private init?(code: ResponseCode, versionData: Data) {
        self.code = code

        guard let version = String(bytes: versionData, encoding: .utf8) else {
            return nil
        }

        self.version = version
    }
}

struct GetStatisticsResponse: Response {
    let code: ResponseCode
    
    let statistics: RileyLinkStatistics

    init?(data: Data) {
        guard data.count > 1, let code = ResponseCode(rawValue: data[data.startIndex]) else {
            return nil
        }
        
        self.init(code: code, data: data[data.startIndex.advanced(by: 1)...])
    }
    
    init?(legacyData data: Data) {
        self.init(code: .success, data: data)
    }

    private init?(code: ResponseCode, data: Data) {
        self.code = code
        
        guard data.count >= 16 else {
            return nil
        }
        
        let uptime = TimeInterval(milliseconds: Double(data[data.startIndex...].toBigEndian(UInt32.self)))
        let radioRxOverflowCount = data[data.startIndex.advanced(by: 4)...].toBigEndian(UInt16.self)
        let radioRxFifoOverflowCount = data[data.startIndex.advanced(by: 6)...].toBigEndian(UInt16.self)
        let packetRxCount = data[data.startIndex.advanced(by: 8)...].toBigEndian(UInt16.self)
        let packetTxCount = data[data.startIndex.advanced(by: 10)...].toBigEndian(UInt16.self)
        let crcFailureCount = data[data.startIndex.advanced(by: 12)...].toBigEndian(UInt16.self)
        let spiSyncFailureCount = data[data.startIndex.advanced(by: 14)...].toBigEndian(UInt16.self)
        
        self.statistics = RileyLinkStatistics(uptime: uptime, radioRxOverflowCount: radioRxOverflowCount, radioRxFifoOverflowCount: radioRxFifoOverflowCount, packetRxCount: packetRxCount, packetTxCount: packetTxCount, crcFailureCount: crcFailureCount, spiSyncFailureCount: spiSyncFailureCount)
    }
}


struct PacketResponse: Response {
    let code: ResponseCode
    let packet: RFPacket?

    init?(data: Data) {
        guard data.count > 0, let code = ResponseCode(rawValue: data[data.startIndex]) else {
            return nil
        }

        switch code {
        case .success:
            guard data.count > 1, let packet = RFPacket(rfspyResponse: data[data.startIndex.advanced(by: 1)...]) else {
                return nil
            }
            self.packet = packet
        case .rxTimeout,
             .commandInterrupted,
             .zeroData,
             .invalidParam,
             .unknownCommand:
            self.packet = nil
        }

        self.code = code
    }

    init?(legacyData data: Data) {
        guard data.count > 0 else {
            return nil
        }

        packet = RFPacket(rfspyResponse: data)

        if packet != nil {
            code = .success
        } else {
            guard let code = ResponseCode(rawValue: data[data.startIndex]) else {
                return nil
            }

            self.code = code
        }
    }

    init(code: ResponseCode, packet: RFPacket?) {
        self.code = code
        self.packet = packet
    }
}
