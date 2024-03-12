//
//  Command.swift
//  RileyLinkBLEKit
//
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import Foundation


// CmdBase
enum RileyLinkCommand: UInt8 {
    case getState         = 1
    case getVersion       = 2
    case getPacket        = 3
    case sendPacket       = 4
    case sendAndListen    = 5
    case updateRegister   = 6
    case reset            = 7
    case setLEDMode       = 8
    case readRegister     = 9
    case setModeRegisters = 10
    case setSWEncoding    = 11
    case setPreamble      = 12
    case resetRadioConfig = 13
    case getStatistics    = 14
}

enum RileyLinkLEDType: UInt8 {
    case green = 0
    case blue = 1
}

protocol Command {
    associatedtype ResponseType: Response

    var data: Data { get }
}

struct GetPacket: Command {
    typealias ResponseType = PacketResponse

    let listenChannel: UInt8
    let timeoutMS: UInt32

    init(listenChannel: UInt8, timeoutMS: UInt32) {
        self.listenChannel = listenChannel
        self.timeoutMS = timeoutMS
    }

    var data: Data {
        var data = Data([
            RileyLinkCommand.getPacket.rawValue,
            listenChannel
        ])
        data.appendBigEndian(timeoutMS)

        return data
    }
}

struct GetVersion: Command {
    typealias ResponseType = GetVersionResponse

    var data: Data {
        return Data([RileyLinkCommand.getVersion.rawValue])
    }
}

struct SendAndListen: Command {
    typealias ResponseType = PacketResponse

    let outgoing: Data

    /// In general, 0 = meter, cgm. 2 = pump
    let sendChannel: UInt8

    /// 0 = no repeat, i.e. only one packet.  1 repeat = 2 packets sent total.
    let repeatCount: UInt8
    let delayBetweenPacketsMS: UInt16
    let listenChannel: UInt8
    let timeoutMS: UInt32
    let retryCount: UInt8
    let preambleExtensionMS: UInt16
    let firmwareVersion: RadioFirmwareVersion

    init(outgoing: Data, sendChannel: UInt8, repeatCount: UInt8, delayBetweenPacketsMS: UInt16, listenChannel: UInt8, timeoutMS: UInt32, retryCount: UInt8, preambleExtensionMS: UInt16, firmwareVersion: RadioFirmwareVersion) {
        self.outgoing = outgoing
        self.sendChannel = sendChannel
        self.repeatCount = repeatCount
        self.delayBetweenPacketsMS = delayBetweenPacketsMS
        self.listenChannel = listenChannel
        self.timeoutMS = timeoutMS
        self.retryCount = retryCount
        self.preambleExtensionMS = preambleExtensionMS
        self.firmwareVersion = firmwareVersion
    }

    var data: Data {
        var data = Data([
            RileyLinkCommand.sendAndListen.rawValue,
            sendChannel,
            repeatCount
        ])
        
        if firmwareVersion.supports16BitPacketDelay {
            data.appendBigEndian(delayBetweenPacketsMS)
        } else {
            data.append(UInt8(clamping: Int(delayBetweenPacketsMS)))
        }
        
        data.append(listenChannel);
        data.appendBigEndian(timeoutMS)
        data.append(retryCount)
        if firmwareVersion.supportsPreambleExtension {
            data.appendBigEndian(preambleExtensionMS)
        }
        data.append(outgoing)

        return data
    }
}

struct SendPacket: Command {
    typealias ResponseType = CodeResponse

    let outgoing: Data

    /// In general, 0 = meter, cgm. 2 = pump
    let sendChannel: UInt8

    /// 0 = no repeat, i.e. only one packet.  1 repeat = 2 packets sent total.
    let repeatCount: UInt8
    let delayBetweenPacketsMS: UInt16
    let preambleExtensionMS: UInt16
    let firmwareVersion: RadioFirmwareVersion

    init(outgoing: Data, sendChannel: UInt8, repeatCount: UInt8, delayBetweenPacketsMS: UInt16, preambleExtensionMS: UInt16, firmwareVersion: RadioFirmwareVersion) {
        self.outgoing = outgoing
        self.sendChannel = sendChannel
        self.repeatCount = repeatCount
        self.delayBetweenPacketsMS = delayBetweenPacketsMS
        self.preambleExtensionMS = preambleExtensionMS
        self.firmwareVersion = firmwareVersion;
    }

    var data: Data {
        var data = Data([
            RileyLinkCommand.sendPacket.rawValue,
            sendChannel,
            repeatCount,
        ])
        if firmwareVersion.supports16BitPacketDelay {
            data.appendBigEndian(delayBetweenPacketsMS)
        } else {
            data.append(UInt8(clamping: Int(delayBetweenPacketsMS)))
        }

        if firmwareVersion.supportsPreambleExtension {
            data.appendBigEndian(preambleExtensionMS)
        }
        data.append(outgoing)

        return data
    }
}

struct RegisterSetting {
    let address: CC111XRegister
    let value: UInt8
}

struct UpdateRegister: Command {
    typealias ResponseType = UpdateRegisterResponse

    enum Response: UInt8 {
        case success = 1
        case invalidRegister = 2
    }

    let register: RegisterSetting
    let firmwareVersion: RadioFirmwareVersion


    init(_ address: CC111XRegister, value: UInt8, firmwareVersion: RadioFirmwareVersion) {
        register = RegisterSetting(address: address, value: value)
        self.firmwareVersion = firmwareVersion
    }

    var data: Data {
        var data = Data([
            RileyLinkCommand.updateRegister.rawValue,
            register.address.rawValue,
            register.value
        ])
        if firmwareVersion.needsExtraByteForUpdateRegisterCommand {
            data.append(0)
        }
        return data
    }
}

struct ReadRegister: Command {
    typealias ResponseType = ReadRegisterResponse
    
    enum Response: UInt8 {
        case success = 1
        case invalidRegister = 2
    }
    
    let address: CC111XRegister
    let firmwareVersion: RadioFirmwareVersion
    
    init(_ address: CC111XRegister, firmwareVersion: RadioFirmwareVersion) {
        self.address = address
        self.firmwareVersion = firmwareVersion
    }
    
    var data: Data {
        var data = Data([
            RileyLinkCommand.readRegister.rawValue,
            address.rawValue,
            ])
        if firmwareVersion.needsExtraByteForReadRegisterCommand {
            data.append(address.rawValue)
        }
        return data
    }
}


struct SetModeRegisters: Command {
    typealias ResponseType = UpdateRegisterResponse

    enum RegisterModeType: UInt8 {
        case tx = 0x01
        case rx = 0x02
    }

    private var settings: [RegisterSetting] = []

    let registerMode: RegisterModeType

    mutating func append(_ registerSetting: RegisterSetting) {
        settings.append(registerSetting)
    }

    var data: Data {
        var data = Data([
            RileyLinkCommand.setModeRegisters.rawValue,
            registerMode.rawValue
        ])

        for setting in settings {
            data.append(setting.address.rawValue)
            data.append(setting.value)
        }

        return data
    }
}

struct SetSoftwareEncoding: Command {
    typealias ResponseType = CodeResponse

    let encodingType: SoftwareEncodingType
    
    
    init(_ encodingType: SoftwareEncodingType) {
        self.encodingType = encodingType
    }
    
    var data: Data {
        return Data([
            RileyLinkCommand.setSWEncoding.rawValue,
            encodingType.rawValue
        ])
    }
}

struct SetPreamble: Command {
    typealias ResponseType = CodeResponse
    
    let preambleValue: UInt16
    
    
    init(_ value: UInt16) {
        self.preambleValue = value
    }
    
    var data: Data {
        var data = Data([RileyLinkCommand.setPreamble.rawValue])
        data.appendBigEndian(preambleValue)
        return data
        
    }
}

struct SetLEDMode: Command {
    typealias ResponseType = CodeResponse
    
    let led: RileyLinkLEDType
    let mode: RileyLinkLEDMode
    
    
    init(_ led: RileyLinkLEDType, mode: RileyLinkLEDMode) {
        self.led = led
        self.mode = mode
    }
    
    var data: Data {
        return Data([RileyLinkCommand.setLEDMode.rawValue, led.rawValue, mode.rawValue])
    }
}


struct ResetRadioConfig: Command {
    typealias ResponseType = CodeResponse
    
    var data: Data {
        return Data([RileyLinkCommand.resetRadioConfig.rawValue])
    }
}

struct GetStatistics: Command {
    typealias ResponseType = GetStatisticsResponse
    
    var data: Data {
        return Data([RileyLinkCommand.getStatistics.rawValue])
    }
}
