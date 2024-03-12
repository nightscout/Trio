//
//  BubbleTransmitter.swift
//  MiaomiaoClient
//
//  Created by LoopKit Authors on 08/01/2020.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import CoreBluetooth
import Foundation
import UIKit
import os.log

public enum BubbleResponseType: UInt8 {
    case dataPacket = 130
    case bubbleInfo = 128 // = wakeUp + device info
    case noSensor = 191
    case serialNumber = 192
    case patchInfo = 193 // 0xC1
     /// bubble firmware 2.6 support decrypt libre2 344 to libre1 344
     /// if firmware >= 2.6, write [0x08, 0x01, 0x00, 0x00, 0x00, 0x2B]
     /// bubble will decrypt the libre2 data and return it
    // we don't really support decrypteddatapacket as we like to decrypt our selves!
    // case decryptedDataPacket = 136 // 0x88
}

extension BubbleResponseType {
    var description: String {
        switch self {
        case .bubbleInfo:
            return "bubbleinfo"
        case .dataPacket:
            return "datapacket"
        case .noSensor:
            return "nosensor"
        case .serialNumber:
            return "serialnumber"
        case .patchInfo:
            return "patchInfo"
        }
    }
}

// The Bubble uses the same serviceUUID,
// writeCharachteristic and notifyCharachteristic
// as the MiaoMiao, but different byte sequences
class BubbleTransmitter: MiaoMiaoTransmitter {
    override class var shortTransmitterName: String {
        "bubble"
    }
    override class var manufacturerer: String {
        "bubbledevteam"
    }

    override class var smallImage: UIImage? {
         UIImage(named: "bubble", in: Bundle.current, compatibleWith: nil)
    }

    override static func canSupportPeripheral(_ peripheral: PeripheralProtocol) -> Bool {
        peripheral.name?.lowercased().starts(with: "bubble") ?? false
    }

    override func reset() {
        rxBuffer.resetAllBytes()
    }

    override class var requiresDelayedReconnect: Bool {
        true
    }

    private var hardware: String? = ""
    private var firmware: String? = ""
    private var mac: String? = ""

    private var patchInfo: Data?
    private var uid: [UInt8]?

    private var battery: Int?

    fileprivate lazy var bLogger = Logger(forType: Self.self)

    override class func getDeviceDetailsFromAdvertisement(advertisementData: [String: Any]?) -> String? {
        let (amac, afirmware, ahardware) = Self.getDeviceDetailsFromAdvertisementInternal(advertisementData: advertisementData)

        if let amac, let ahardware, let afirmware {
            return "\(amac)\n HW:\(ahardware), FW: \(afirmware)"
        }

        return nil
    }

    private static func getDeviceDetailsFromAdvertisementInternal(advertisementData: [String: Any]?) -> (String?, String?, String?) {

        guard let data = advertisementData?[CBAdvertisementDataManufacturerDataKey] as? Data else {
            return (nil, nil, nil)
        }
        var mac = ""
        for i in 0 ..< 6 {
            mac += data.subdata(in: (7 - i)..<(8 - i)).hexEncodedString().uppercased()
            if i != 5 {
                mac += ":"
            }
        }

        guard  data.count >= 12 else {
            return (nil, nil, nil)
        }

        let fSub1 = Data(repeating: data[8], count: 1)
        let fSub2 = Data(repeating: data[9], count: 1)
        let firmware = Float("\(fSub1.hexEncodedString()).\(fSub2.hexEncodedString())")?.description

        let hSub1 = Data(repeating: data[10], count: 1)
        let hSub2 = Data(repeating: data[11], count: 1)

        let hardware = Float("\(hSub1.hexEncodedString()).\(hSub2.hexEncodedString())")?.description
        return (mac, firmware, hardware)
    }

    required init(delegate: LibreTransmitterDelegate, advertisementData: [String: Any]?) {
        // advertisementData is unknown for the miaomiao

        super.init(delegate: delegate, advertisementData: advertisementData)
        // self.delegate = delegate
        // deviceFromAdvertisementData(advertisementData: advertisementData)
        (self.mac, self.firmware, self.hardware) = Self.getDeviceDetailsFromAdvertisementInternal(advertisementData: advertisementData)
    }

    override func requestData(writeCharacteristics: CBCharacteristic, peripheral: CBPeripheral) {
        bLogger.debug("bubbleRequestData")
        reset()

        let data = Data([0x00, 0x00, 0x05])
        delegate?.libreDeviceLogMessage(payload: "Bubble Transmitter: requesting data transmission every five minutes: \(data.toDebugString())", type: .send)
        peripheral.writeValue(data, for: writeCharacteristics, type: .withResponse)
    }
    override func updateValueForNotifyCharacteristics(_ value: Data, peripheral: CBPeripheral, writeCharacteristic: CBCharacteristic?) {
        bLogger.debug("bubbleDidUpdateValueForNotifyCharacteristics, firstbyte is: \(value.first.debugDescription)")
        guard let firstByte = value.first, let bubbleResponseState = BubbleResponseType(rawValue: firstByte) else {
           return
        }
        bLogger.debug("bubble responsestate is of type \(bubbleResponseState.description)")
        bLogger.debug("bubble value is: \(value.toDebugString())")
        delegate?.libreDeviceLogMessage(payload: "Bubble received value: \(value.toDebugString())", type: .receive)
        
        switch bubbleResponseState {
        case .bubbleInfo:
            // let hardware = value[value.count-2].description + "." + value[value.count-1].description
            // let firmware = value[2].description + "." + value[3].description
           // let patchInfo = Data(Double(firmware)! < 1.35 ? value[3...8] : value[5...10])
            battery = Int(value[4])

            bLogger.debug("Got bubbledevice: \(self.metadata.debugDescription)")
           if let writeCharacteristic {
               let data = Data([0x02, 0x00, 0x00, 0x00, 0x00, 0x2B])
               delegate?.libreDeviceLogMessage(payload: "Bubble requesting datapacket: \(data.toDebugString())", type: .send)
               peripheral.writeValue(data, for: writeCharacteristic, type: .withResponse)
           }
        case .dataPacket:// , .decryptedDataPacket:
           rxBuffer.append(value.suffix(from: 4))
            bLogger.debug("aggregated datapacket is now of length: \(self.rxBuffer.count)")
           if rxBuffer.count >= 352 {
               handleCompleteMessage()
               reset()
           }
        case .noSensor:
            delegate?.libreDeviceReceivedMessage(0x34, payloadData: rxBuffer)

            reset()
        case .serialNumber:
            guard value.count >= 10 else { return }
            reset()
            self.uid = [UInt8](value.subdata(in: 2..<10))

            // for historical reasons
            rxBuffer.append(value.subdata(in: 2..<10))

        case .patchInfo:
            guard value.count >= 10 else {
                bLogger.debug("not able to extract patchinfo")
                return
            }
            patchInfo = value.subdata(in: 5 ..< 11)
        }
    }

    private var rxBuffer = Data()
    private var sensorData: SensorData?
    private var metadata: LibreTransmitterMetadata?

    override func handleCompleteMessage() {
        bLogger.debug("bubbleHandleCompleteMessage")

        guard rxBuffer.count >= 352 else {
            return
        }

        metadata = .init(hardware: hardware ?? "unknown",
                         firmware: firmware ?? "unknown",
                         battery: battery ?? 100,
                         name: Self.shortTransmitterName,
                         macAddress: self.mac,
                         patchInfo: patchInfo, uid: self.uid)

        let data = rxBuffer.subdata(in: 8..<352)
        bLogger.debug("bubbleHandleCompleteMessage raw data: \([UInt8](self.rxBuffer))")
        sensorData = SensorData(uuid: rxBuffer.subdata(in: 0..<8), bytes: [UInt8](data), date: Date())

        bLogger.debug("bubble got sensordata \(self.sensorData.debugDescription) and metadata \(self.metadata.debugDescription), delegate is \(self.delegate.debugDescription)")

        if var sensorData, let metadata {
            if let patchInfo = metadata.patchInfo {
                sensorData.patchInfo = patchInfo
            }
            delegate?.libreTransmitterDidUpdate(with: sensorData, and: metadata)
        }
    }
}
