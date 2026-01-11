//
//  ConfigureAlertsCommand.swift
//  OmniBLE
//
//  From OmniKit/MessageTransport/MessageBlocks/ConfigureAlertsCommand.swift
//  Created by Pete Schwamb on 2/22/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

public struct ConfigureAlertsCommand : NonceResyncableMessageBlock {
    
    public let blockType: MessageBlockType = .configureAlerts
    
    public var nonce: UInt32
    let configurations: [AlertConfiguration]
    
    public var data: Data {
        var data = Data([
            blockType.rawValue,
            UInt8(4 + configurations.count * AlertConfiguration.length),
            ])
        data.appendBigEndian(nonce)
        // Sorting the alerts not required, but it can be helpful for log analysis
        let sorted = configurations.sorted { $0.slot.rawValue < $1.slot.rawValue }
        for config in sorted {
            data.append(contentsOf: config.data)
        }
        return data
    }
    
    public init(encodedData: Data) throws {
        if encodedData.count < 10 {
            throw MessageBlockError.notEnoughData
        }
        self.nonce = encodedData[2...].toBigEndian(UInt32.self)
        
        let length = Int(encodedData[1])
        
        let numConfigs = (length - 4) / AlertConfiguration.length
        
        var configs = [AlertConfiguration]()
        
        for i in 0..<numConfigs {
            let offset = 2 + 4 + i * AlertConfiguration.length
            configs.append(try AlertConfiguration(encodedData: encodedData.subdata(in: offset..<(offset+6))))
        }
        self.configurations = configs
    }
    
    public init(nonce: UInt32, configurations: [AlertConfiguration]) {
        self.nonce = nonce
        self.configurations = configurations
    }
}

// MARK: - AlertConfiguration encoding/decoding
extension AlertConfiguration {
    public init(encodedData: Data) throws {
        if encodedData.count < 6 {
            throw MessageBlockError.notEnoughData
        }

        let alertTypeBits = encodedData[0] >> 4
        guard let alertType = AlertSlot(rawValue: alertTypeBits) else {
            throw MessageError.unknownValue(value: alertTypeBits, typeDescription: "AlertType")
        }
        self.slot = alertType

        self.active = encodedData[0] & 0b1000 != 0

        self.autoOffModifier = encodedData[0] & 0b10 != 0

        self.duration = TimeInterval(minutes: Double((Int(encodedData[0] & 0b1) << 8) + Int(encodedData[1])))

        let yyyy = (Int(encodedData[2]) << 8) + (Int(encodedData[3])) & 0x3fff

        if encodedData[0] & 0b100 != 0 {
            let volume = Double(yyyy * 2) / Pod.pulsesPerUnit
            self.trigger = .unitsRemaining(volume)
        } else {
            self.trigger = .timeUntilAlert(TimeInterval(minutes: Double(yyyy)))
        }

        let beepRepeatBits = encodedData[4]
        guard let beepRepeat = BeepRepeat(rawValue: beepRepeatBits) else {
            throw MessageError.unknownValue(value: beepRepeatBits, typeDescription: "BeepRepeat")
        }
        self.beepRepeat = beepRepeat

        let beepTypeBits = encodedData[5]
        guard let beepType = BeepType(rawValue: beepTypeBits) else {
            throw MessageError.unknownValue(value: beepTypeBits, typeDescription: "BeepType")
        }
        self.beepType = beepType

        self.silent = (beepType == .noBeepNonCancel)
    }

    public var data: Data {
        var firstByte = slot.rawValue << 4
        firstByte += active ? (1 << 3) : 0

        if case .unitsRemaining = trigger {
            firstByte += 1 << 2
        }
        if autoOffModifier {
            firstByte += 1 << 1
        }

        // The 9-bit duration is limited to 2^9-1 minutes max value
        let durationMinutes = min(UInt(duration.minutes), 0x1ff)

        // High bit of duration
        firstByte += UInt8((durationMinutes >> 8) & 0x1)

        var data = Data([
            firstByte,
            UInt8(durationMinutes & 0xff)
            ])

        switch trigger {
        case .unitsRemaining(let volume):
            let ticks = UInt16(volume / Pod.pulseSize / 2)
            data.appendBigEndian(ticks)
        case .timeUntilAlert(let secondsUntilAlert):
            // round the time to alert to the nearest minute
            let minutes = UInt16((secondsUntilAlert + 30).minutes)
            data.appendBigEndian(minutes)
        }
        data.append(beepRepeat.rawValue)
        let beepTypeToSet: BeepType = silent ? .noBeepNonCancel : beepType
        data.append(beepTypeToSet.rawValue)

        return data
    }
}

extension ConfigureAlertsCommand: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "ConfigureAlertsCommand(nonce:\(Data(bigEndian: nonce).hexadecimalString), configurations:\(configurations))"
    }
}
