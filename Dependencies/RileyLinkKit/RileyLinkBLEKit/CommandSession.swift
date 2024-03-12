//
//  RileyLinkCmdSession.swift
//  RileyLinkBLEKit
//
//  Created by Pete Schwamb on 10/8/17.
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import Foundation

public enum RXFilterMode: UInt8 {
    case wide   = 0x50  // 300KHz
    case narrow = 0x90  // 150KHz
}

public enum SoftwareEncodingType: UInt8 {
    case none       = 0x00
    case manchester = 0x01
    case fourbsixb  = 0x02
}

public enum CC111XRegister: UInt8 {
    case sync1    = 0x00
    case sync0    = 0x01
    case pktlen   = 0x02
    case pktctrl1 = 0x03
    case pktctrl0 = 0x04
    case fsctrl1  = 0x07
    case freq2    = 0x09
    case freq1    = 0x0a
    case freq0    = 0x0b
    case mdmcfg4  = 0x0c
    case mdmcfg3  = 0x0d
    case mdmcfg2  = 0x0e
    case mdmcfg1  = 0x0f
    case mdmcfg0  = 0x10
    case deviatn  = 0x11
    case mcsm0    = 0x14
    case foccfg   = 0x15
    case agcctrl2 = 0x17
    case agcctrl1 = 0x18
    case agcctrl0 = 0x19
    case frend1   = 0x1a
    case frend0   = 0x1b
    case fscal3   = 0x1c
    case fscal2   = 0x1d
    case fscal1   = 0x1e
    case fscal0   = 0x1f
    case test1    = 0x24
    case test0    = 0x25
    case paTable0 = 0x2e
}

public struct RileyLinkStatistics {
    public let uptime: TimeInterval
    public let radioRxOverflowCount: UInt16
    public let radioRxFifoOverflowCount: UInt16
    public let packetRxCount: UInt16
    public let packetTxCount: UInt16
    public let crcFailureCount: UInt16
    public let spiSyncFailureCount: UInt16
    
    public init(uptime: TimeInterval, radioRxOverflowCount: UInt16, radioRxFifoOverflowCount: UInt16, packetRxCount: UInt16, packetTxCount: UInt16, crcFailureCount: UInt16, spiSyncFailureCount: UInt16) {
        self.uptime = uptime
        self.radioRxOverflowCount = radioRxOverflowCount
        self.radioRxFifoOverflowCount = radioRxFifoOverflowCount
        self.packetRxCount = packetRxCount
        self.packetTxCount = packetTxCount
        self.crcFailureCount = crcFailureCount
        self.spiSyncFailureCount = spiSyncFailureCount
    }
    
}

public struct CommandSession {
    let manager: PeripheralManager
    let responseType: PeripheralManager.ResponseType
    public let firmwareVersion: RadioFirmwareVersion

    /// Invokes a command expecting a response
    ///
    /// Unsuccessful responses are thrown as errors.
    ///
    /// - Parameters:
    ///   - command: The command
    ///   - timeout: The amount of time to wait for the pump to respond before throwing a timeout error. This should not include any expected BLE latency.
    /// - Returns: The successful response
    /// - Throws: RileyLinkDeviceError
    private func writeCommand<C: Command>(_ command: C, timeout: TimeInterval) throws -> C.ResponseType {
        let response = try manager.writeCommand(command,
            timeout: timeout + PeripheralManager.expectedMaxBLELatency,
            responseType: responseType
        )

        switch response.code {
        case .rxTimeout:
            throw RileyLinkDeviceError.responseTimeout
        case .commandInterrupted:
            throw RileyLinkDeviceError.responseTimeout
        case .zeroData:
            throw RileyLinkDeviceError.invalidResponse(Data())
        case .invalidParam:
            throw RileyLinkDeviceError.errorResponse("RileyLink reported invalid param: " + command.data.hexadecimalString)
        case .unknownCommand:
            throw RileyLinkDeviceError.errorResponse("RileyLink reported unknown command: " + command.data.hexadecimalString)
        case .success:
            return response
        }
    }

    /// Invokes a command expecting an RF packet response
    ///
    /// - Parameters:
    ///   - command: The command
    ///   - timeout: The amount of time to wait for the pump to respond before throwing a timeout error. This should not include any expected BLE latency.
    /// - Returns: The successful packet response
    /// - Throws: RileyLinkDeviceError
    private func writeCommand<C: Command>(_ command: C, timeout: TimeInterval) throws -> RFPacket where C.ResponseType == PacketResponse {
        let response: C.ResponseType = try writeCommand(command, timeout: timeout)

        guard let packet = response.packet else {
            throw RileyLinkDeviceError.invalidResponse(Data())
        }
        return packet
    }

    /// - Throws: RileyLinkDeviceError
    public func updateRegister(_ address: CC111XRegister, value: UInt8) throws {
        let command = UpdateRegister(address, value: value, firmwareVersion: firmwareVersion)
        _ = try writeCommand(command, timeout: 0)
    }
    
    /// - Throws: RileyLinkDeviceError
    public func readRegister(_ address: CC111XRegister) throws -> UInt8 {
        guard firmwareVersion.supportsReadRegister else {
            throw RileyLinkDeviceError.unsupportedCommand(String(describing: RileyLinkCommand.readRegister))
        }
        
        let command = ReadRegister(address, firmwareVersion: firmwareVersion)
        let response: ReadRegisterResponse = try writeCommand(command, timeout: 0)
        
        guard response.code == .success else {
            throw RileyLinkDeviceError.errorResponse("Unsupported register: \(String(describing: address))")
        }

        return response.value
    }

    
    /// - Throws: RileyLinkDeviceError
    public func setCCLEDMode(_ mode: RileyLinkLEDMode) throws {
        let ccMode: RileyLinkLEDMode
        
        switch mode {
        case .on:
            ccMode = .auto
        default:
            ccMode = .off
        }
        
        let enableBlue = SetLEDMode(.blue, mode: ccMode)
        _ = try writeCommand(enableBlue, timeout: 0)
        let enableGreen = SetLEDMode(.green, mode: ccMode)
        _ = try writeCommand(enableGreen, timeout: 0)
    }

    private static let xtalFrequency = Measurement<UnitFrequency>(value: 24, unit: .megahertz)

    /// - Throws: RileyLinkDeviceError
    public func setBaseFrequency(_ frequency: Measurement<UnitFrequency>) throws {
        let val = Int(
            frequency.converted(to: .hertz).value /
            (CommandSession.xtalFrequency / pow(2, 16)).converted(to: .hertz).value)

        try updateRegister(.freq0, value: UInt8(val & 0xff))
        try updateRegister(.freq1, value: UInt8((val >> 8) & 0xff))
        try updateRegister(.freq2, value: UInt8((val >> 16) & 0xff))
    }
    
    public func readBaseFrequency() throws -> Measurement<UnitFrequency> {
        let freq0 = try readRegister(.freq0)
        let freq1 = try readRegister(.freq1)
        let freq2 = try readRegister(.freq2)

        let value = Double(UInt32(freq0) + (UInt32(freq1) << 8) + (UInt32(freq2) << 16))

        let frequency = value * (CommandSession.xtalFrequency / pow(2, 16)).converted(to: .hertz).value

        return Measurement<UnitFrequency>(value: frequency, unit: .hertz).converted(to: .megahertz)
    }
    
    /// Sends data to the pump, listening for a reply
    ///
    /// - Parameters:
    ///   - data: The data to send
    ///   - repeatCount: The number of times to repeat the message before listening begins
    ///   - timeout: The length of time to listen for a response before timing out
    ///   - retryCount: The number of times to repeat the send & listen sequence
    ///   - preambleExtension: If set, the length of time to continuously send preamble data. Overrides the register based preamble settings.
    /// - Returns: The packet reply
    /// - Throws: RileyLinkDeviceError
    public func sendAndListen(_ data: Data, repeatCount: Int, timeout: TimeInterval, retryCount: Int, preambleExtension: TimeInterval?) throws -> RFPacket {
        let delayBetweenPackets: TimeInterval = 0

        let command = SendAndListen(
            outgoing: data,
            sendChannel: 0,
            repeatCount: UInt8(clamping: repeatCount),
            delayBetweenPacketsMS: UInt16(clamping: Int(delayBetweenPackets)),
            listenChannel: 0,
            timeoutMS: UInt32(clamping: Int(timeout.milliseconds)),
            retryCount: UInt8(clamping: retryCount),
            preambleExtensionMS: UInt16(clamping: Int(preambleExtension?.milliseconds ?? 0)),
            firmwareVersion: firmwareVersion
        )

        // At least 17 ms between packets for radio to stop/start
        let radioTimeBetweenPackets = TimeInterval(milliseconds: 17)
        let timeBetweenPackets = delayBetweenPackets + radioTimeBetweenPackets

        // 16384 = bitrate, 8 = bits per byte
        let singlePacketSendTime: TimeInterval = (Double(data.count * 8) / 16_384)
        let preambleTime = preambleExtension ?? 0
        let totalRepeatSendTime: TimeInterval = (singlePacketSendTime + timeBetweenPackets + preambleTime) * Double(repeatCount+1)
        let totalTimeout = (totalRepeatSendTime + timeout) * Double(retryCount + 1)
        return try writeCommand(command, timeout: totalTimeout)
    }
    
    /// Sends data to the pump, listening for a reply
    ///
    /// - Parameters:
    ///   - data: The data to send
    ///   - repeatCount: The number of times to repeat the message before listening begins
    ///   - timeout: The length of time to listen for a response before timing out
    ///   - retryCount: The number of times to repeat the send & listen sequence if no response is heard
    /// - Returns: The packet reply
    /// - Throws: RileyLinkDeviceError
    public func sendAndListen(_ data: Data, repeatCount: Int, timeout: TimeInterval, retryCount: Int) throws -> RFPacket {
        return try sendAndListen(data, repeatCount: repeatCount, timeout: timeout, retryCount: retryCount, preambleExtension: nil)
    }


    /// - Throws: RileyLinkDeviceError
    public func listen(onChannel channel: Int, timeout: TimeInterval) throws -> RFPacket? {
        let command = GetPacket(
            listenChannel: 0,
            timeoutMS: UInt32(clamping: Int(timeout.milliseconds))
        )

        return try writeCommand(command, timeout: timeout)
    }

    /// - Throws: RileyLinkDeviceError
    public func send(_ data: Data, onChannel channel: Int, timeout: TimeInterval) throws {
        let command = SendPacket(
            outgoing: data,
            sendChannel: UInt8(clamping: channel),
            repeatCount: 0,
            delayBetweenPacketsMS: 0,
            preambleExtensionMS: 0,
            firmwareVersion: firmwareVersion
        )

        _ = try writeCommand(command, timeout: timeout)
    }
    
    /// - Throws: RileyLinkDeviceError
    public func setSoftwareEncoding(_ swEncodingType: SoftwareEncodingType) throws {
        guard firmwareVersion.supportsSoftwareEncoding else {
            throw RileyLinkDeviceError.unsupportedCommand(String(describing: RileyLinkCommand.setSWEncoding))
        }
        
        let command = SetSoftwareEncoding(swEncodingType)
        
        let response = try writeCommand(command, timeout: 0)
        
        guard response.code == .success else {
            throw RileyLinkDeviceError.unsupportedCommand("Set Software Encoding error")
        }
    }
    
    public func resetRadioConfig() throws {
        guard firmwareVersion.supportsResetRadioConfig else {
            return
        }
        
        let command = ResetRadioConfig()
        _ = try writeCommand(command, timeout: 0)
    }
    
    public func getRileyLinkStatistics() throws -> RileyLinkStatistics {
        guard firmwareVersion.supportsRileyLinkStatistics else {
            throw RileyLinkDeviceError.unsupportedCommand(String(describing: RileyLinkCommand.getStatistics))
        }
        
        let command = GetStatistics()
        let response: GetStatisticsResponse = try writeCommand(command, timeout: 0)
        
        return response.statistics
    }
    
    public func setPreamble(_ preambleValue: UInt16) throws {
        guard firmwareVersion.supportsCustomPreamble else {
            throw RileyLinkDeviceError.unsupportedCommand(String(describing: RileyLinkCommand.setPreamble))
        }
        
        let command = SetPreamble(preambleValue)
        
        _ = try writeCommand(command, timeout: 0)
    }

    /// Asserts that the caller is currently on the session's queue
    public func assertOnSessionQueue() {
        dispatchPrecondition(condition: .onQueue(manager.queue))
    }
}
