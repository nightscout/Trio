//
//  MiaomiaoTransmitter.swift
//  MiaomiaoClient
//
//  Created by LoopKit Authors on 01/08/2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//
//  How does the MiaoMiao work?
//
//    0.) Advertising
//        MiaoMiao advertises with the following data:
//        - key : "kCBAdvDataIsConnectable"     - value : 1
//        - key : "kCBAdvDataManufacturerData"  - value : <0034cb1c 53093fb4> -> This might be usable as a unique device id.
//        - key : "kCBAdvDataLocalName"         - value : miaomiao
//
//    1.) Services
///       The MiaoMiao has two bluetooth services, one provided for the open source community and one that is probably to be used by the Tomato app.
//        a) UUID: 6E400001-B5A3-F393-E0A9-E50E24DCCA9E -> Open Source Community
//           Did discover service: <CBService: 0x1c4673a00, isPrimary = YES, UUID = 6E400001-B5A3-F393-E0A9-E50E24DCCA9E>
//        b) UUID: 00001532-1212-EFDE-1523-785FEABCD123
//           Did discover service: <CBService: 0x1c0a61880, isPrimary = YES, UUID = 00001530-1212-EFDE-1523-785FEABCD123>
//
//    2.) Characteristics for open source service with UUID 6E400001-B5A3-F393-E0A9-E50E24DCCA9E
//
//        The service contains two characheristics:
//
//          a) Notify_Characteristic
//             UUID: 6E400003-B5A3-F393-E0A9-E50E24DCCA9E
//             "<CBCharacteristic: 0x1c02ae7c0, UUID = 6E400003-B5A3-F393-E0A9-E50E24DCCA9E, properties = 0x10, value = (null), notifying = NO>"
//                 ... with properties:
//             __C.CBCharacteristicProperties(rawValue: 16)
//             Broadcast:                            [false]
//             Read:                                 [false]
//             WriteWithoutResponse:                 [false]
//             Write:                                [false]
//             Notify:                               [true]
//             Indicate:                             [false]
//             AuthenticatedSignedWrites:            [false]
//             ExtendedProperties:                   [false]
//             NotifyEncryptionRequired:             [false]
//             BroaIndicateEncryptionRequireddcast:  [false]
//             Service for Characteristic:           ["<CBService: 0x1c087f940, isPrimary = YES, UUID = 6E400001-B5A3-F393-E0A9-E50E24DCCA9E>"]
//
//          b) Write_Characteristic
//             UUID: 6E400002-B5A3-F393-E0A9-E50E24DCCA9E
//             "<CBCharacteristic: 0x1c02a81c0, UUID = 6E400002-B5A3-F393-E0A9-E50E24DCCA9E, properties = 0xC, value = (null), notifying = NO>"
//                 ... with properties:
//             __C.CBCharacteristicProperties(rawValue: 12)
//             Broadcast:                            [false]
//             Read:                                 [false]
//             WriteWithoutResponse:                 [true]
//             Write:                                [true]
//             Notify:                               [false]
//             Indicate:                             [false]
//             AuthenticatedSignedWrites:            [false]
//             ExtendedProperties:                   [false]
//             NotifyEncryptionRequired:             [false]
//             BroaIndicateEncryptionRequireddcast:  [false]
//             Service for Characteristic:           ["<CBService: 0x1c087f940, isPrimary = YES, UUID = 6E400001-B5A3-F393-E0A9-E50E24DCCA9E>"]
//
//      3.) Characteristics for (possibly) Tomato app services with UUID 00001532-1212-EFDE-1523-785FEABCD123
//
//          The service contains three characteristics
//
//          a) Read characteristic
//             "<CBCharacteristic: 0x1c42a8c40, UUID = 00001534-1212-EFDE-1523-785FEABCD123, properties = 0x2, value = (null), notifying = NO>"
//                 ... with properties:
//             __C.CBCharacteristicProperties(rawValue: 2)
//             Broadcast:                            [false]
//             Read:                                 [true]
//             WriteWithoutResponse:                 [false]
//             Write:                                [false]
//             Notify:                               [false]
//             Indicate:                             [false]
//             AuthenticatedSignedWrites:            [false]
//             ExtendedProperties:                   [false]
//             NotifyEncryptionRequired:             [false]
//             BroaIndicateEncryptionRequireddcast:  [false]
//             Service for Characteristic:           ["<CBService: 0x1c0a61880, isPrimary = YES, UUID = 00001530-1212-EFDE-1523-785FEABCD123>"]
//
//          b) Write without respons characteristic
//             Characteristic:
//             "<CBCharacteristic: 0x1c42a2220, UUID = 00001532-1212-EFDE-1523-785FEABCD123, properties = 0x4, value = (null), notifying = NO>"
//             ... with properties:
//             __C.CBCharacteristicProperties(rawValue: 4)
//             Broadcast:                            [false]
//             Read:                                 [false]
//             WriteWithoutResponse:                 [true]
//             Write:                                [false]
//             Notify:                               [false]
//             Indicate:                             [false]
//             AuthenticatedSignedWrites:            [false]
//             ExtendedProperties:                   [false]
//             NotifyEncryptionRequired:             [false]
//             BroaIndicateEncryptionRequireddcast:  [false]
//             Service for Characteristic:           ["<CBService: 0x1c0a61880, isPrimary = YES, UUID = 00001530-1212-EFDE-1523-785FEABCD123>"]
//
//          c) Write and notify characteristic
//             "<CBCharacteristic: 0x1c02a8220, UUID = 00001531-1212-EFDE-1523-785FEABCD123, properties = 0x18, value = (null), notifying = NO>"
//                 ... with properties:
//             __C.CBCharacteristicProperties(rawValue: 24)
//             Broadcast:                            [false]
//             Read:                                 [false]
//             WriteWithoutResponse:                 [false]
//             Write:                                [true]
//             Notify:                               [true]
//             Indicate:                             [false]
//             AuthenticatedSignedWrites:            [false]
//             ExtendedProperties:                   [false]
//             NotifyEncryptionRequired:             [false]
//             BroaIndicateEncryptionRequireddcast:  [false]
//             Service for Characteristic:           ["<CBService: 0x1c0a61880, isPrimary = YES, UUID = 00001530-1212-EFDE-1523-785FEABCD123>"]
//
//  The MiaoMiao protocol
//  1.) Data
//      TX: 0xF0
//          Request all the data or the sensor. The bluetooth will return the data at a certain frequency (default is every 5 minutes) after the request
//      RX:
//          a) Data (363 bytes):
//             Pos.  0 (0x00): 0x28 +
//             Pos.  1 (0x01): Len[2 bytes] +
//             Pos.  3 (0x03): Index [2 bytes] (this is the minute counter of the Freestyle Libre sensor) +
//             Pos.  5 (0x05): ID [8 bytes] +
//             Pos. 13 (0x0D): xbattery level in percent [1 byte] (e.g. 0x64 which is 100 in decimal means 100%?)
//             Pos. 14 (0x0E): firmware version [2 bytes] +
//             Pos. 16 (0x10): hardware version [2 bytes] +
//             Pos. 18 (0x12): FRAM data (43 x 8 bytes = 344 bytes) +
//             Pos. end      : 0x29
//             Example: 28  07b3  5457  db353e01 00a007e0  64  0034 0001  11b6e84f050003 875104 57540000 00 000000 00000000 0000b94b 060f1600 c0da6a80 1600c0d6 6a801600
//                      0x28   -> marks begin of data response
//                      0x07b3 -> len is 1971 bytes (= 1952 for FRAM and 19 bytes for all the rest from 0x28 to 0x29, both of which are included)
//                                but as of 2018-03-12 only 1791 bytes are sent.
//                      0x5457 -> index is 21591
//                      0xdb353e0100a007e0 -> id, can be converted to serial number
//                      0x64   -> battery level (= 100%)
//                      0x0034 -> firmware version
//                      0x0001 -> hardware version
//                      0x11b6e84f05000387 FRAM block 0x00 (sensor is expired since byte 0x04 has value 0x05)
//                      0x5104575400000000 FRAM block 0x01
//                      0x0000000000000000 FRAM block 0x02
//                      0xb94b060f1600c0da FRAM block 0x03
//                       ...
//            28 07b3 182b  9a8150 0100a007 e0640034 0001539d
//          b) A new sensor has been detected
//             0x32
//          c) No sensor has been detected
//             0x34
//
//  2.) Confirm to replace the sensor (if a new sensor is detected and shall be used, send this)
//      TX: 0xD301
//  3.) Confirm not to replace the sensor (if a new sensor is detected and shall not be used, send this)
//      TX: 0xD300
//  4.) Change the frequence of data transmission
//      TX: 0xD1XX, where XX is the intervall time, 1 byte, e.g. 0x0A is 10 minutes
//      RX:
//          a) 0xD101 Success
//          b) 0xD100 Fail

import CoreBluetooth
import Foundation
import os.log
import UIKit
public enum MiaoMiaoResponseState: UInt8 {
    case dataPacketReceived = 0x28
    case newSensor = 0x32
    case noSensor = 0x34
    case frequencyChangedResponse = 0xD1
}
extension MiaoMiaoResponseState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .dataPacketReceived:
            return "Data packet received"
        case .newSensor:
            return "New sensor detected"
        case .noSensor:
            return "No sensor found"
        case .frequencyChangedResponse:
            return "Reading intervall changed"
        }
    }
}

class MiaoMiaoTransmitter: LibreTransmitterProxyProtocol {

    fileprivate lazy var logger = Logger(forType: Self.self)

    func reset() {
        rxBuffer.resetAllBytes()
    }

    class var manufacturerer: String {
        "Tomato"
    }

    class var smallImage: UIImage? {
        UIImage(named: "miaomiao-small", in: Bundle.current, compatibleWith: nil)
    }

    class var shortTransmitterName: String {
        "miaomiao"
    }

    class var requiresDelayedReconnect: Bool {
        true
    }

    static var writeCharacteristic: UUIDContainer? = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    static var notifyCharacteristic: UUIDContainer? = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
    static var serviceUUID: [UUIDContainer] = ["6E400001-B5A3-F393-E0A9-E50E24DCCA9E"]

    weak var delegate: LibreTransmitterDelegate?

    private var rxBuffer = Data()
    private var sensorData: SensorData?
    private var metadata: LibreTransmitterMetadata?

    class func canSupportPeripheral(_ peripheral: PeripheralProtocol) -> Bool {
        peripheral.name?.lowercased().starts(with: "miaomiao") ?? false
    }

    class func getDeviceDetailsFromAdvertisement(advertisementData: [String: Any]?) -> String? {
        nil
    }

    required init(delegate: LibreTransmitterDelegate, advertisementData: [String: Any]?) {
        // advertisementData is unknown for the miaomiao
        self.delegate = delegate
    }

    func requestData(writeCharacteristics: CBCharacteristic, peripheral: CBPeripheral) {
        confirmSensor(peripheral: peripheral, writeCharacteristics: writeCharacteristics)
        reset()
        logger.debug("miaomiaoRequestData")

        let data = Data([0xF0])
        delegate?.libreDeviceLogMessage(payload: "Miaomaio requesting data: \(data.toDebugString())", type: .send)
        peripheral.writeValue(data, for: writeCharacteristics, type: .withResponse)
    }

    func updateValueForNotifyCharacteristics(_ value: Data, peripheral: CBPeripheral, writeCharacteristic: CBCharacteristic?) {
        rxBuffer.append(value)

        logger.debug("miaomiao Appended value with length  \(String(describing: value.count)), buffer length is: \(String(describing: self.rxBuffer.count))")

        // When spreading a message over multiple telegrams, the miaomiao protocol
        // does not repeat that initial byte
        // firstbyte is therefore written to rxbuffer on first received telegram
        // this becomes sort of a state to track which message is actually received.
        // Therefore it also becomes important that once a message is fully received, the buffer is invalidated
        //
        guard let firstByte = rxBuffer.first, let miaoMiaoResponseState = MiaoMiaoResponseState(rawValue: firstByte) else {
            reset()
            logger.error("miaomiaoDidUpdateValueForNotifyCharacteristics did not undestand what to do (internal error")
            return
        }
        
        delegate?.libreDeviceLogMessage(payload: "miaomiao received value: \(value.toDebugString())", type: .receive)

        switch miaoMiaoResponseState {
        case .dataPacketReceived: // 0x28: // data received, append to buffer and inform delegate if end reached

            if rxBuffer.count >= 363 {

                delegate?.libreDeviceReceivedMessage(0x28, payloadData: rxBuffer)

                handleCompleteMessage()
                reset()
            }

        case .newSensor: // 0x32: // A new sensor has been detected -> acknowledge to use sensor and reset buffer
            delegate?.libreDeviceReceivedMessage(0x32, payloadData: rxBuffer)

            confirmSensor(peripheral: peripheral, writeCharacteristics: writeCharacteristic)
            reset()
        case .noSensor: // 0x34: // No sensor has been detected -> reset buffer (and wait for new data to arrive)

            delegate?.libreDeviceReceivedMessage(0x34, payloadData: rxBuffer)

            reset()
        case .frequencyChangedResponse: // 0xD1: // Success of fail for setting time intervall

            delegate?.libreDeviceReceivedMessage(0xD1, payloadData: rxBuffer)

            if value.count >= 2 {
                if value[2] == 0x01 {
                    // success setting time interval
                } else if value[2] == 0x00 {
                    // faioure
                } else {
                    // "Unkown response for setting time interval."
                }
            }
            reset()
        }
    }

    func handleCompleteMessage() {
        guard rxBuffer.count >= 363 else {
            return
        }

        var patchInfo: Data?

        if rxBuffer.count >= 369 {
            patchInfo = Data(rxBuffer[363...368])
        }

        logger.debug("rxbuffer length: \(self.rxBuffer.count ), patchinfo: \(String(describing: patchInfo))")

        metadata = LibreTransmitterMetadata(
            hardware: String(describing: rxBuffer[16...17].hexEncodedString()),
            firmware: String(describing: rxBuffer[14...15].hexEncodedString()),
            battery: Int(rxBuffer[13]),
            name: Self.shortTransmitterName,
            macAddress: nil,
            patchInfo: patchInfo,
            uid: [UInt8](rxBuffer[5..<13]) )

        sensorData = SensorData(uuid: Data(rxBuffer.subdata(in: 5..<13)), bytes: [UInt8](rxBuffer.subdata(in: 18..<362)), date: Date())

       if var sensorData, let metadata {
           if let patchInfo = metadata.patchInfo {
               sensorData.patchInfo = patchInfo
           }
           delegate?.libreTransmitterDidUpdate(with: sensorData, and: metadata)
        }
    }

    // Confirm (to replace) the sensor. Iif a new sensor is detected and shall be used, send this command (0xD301)
    func confirmSensor(peripheral: CBPeripheral, writeCharacteristics: CBCharacteristic?) {
        guard let writeCharacteristics else {
            logger.error("could not confirm sensor")
            return
        }
        logger.debug("confirming new sensor")
        let data = Data([0xD3, 0x01])
        delegate?.libreDeviceLogMessage(payload: "Miaomiao auto confirming new sensor: \(data)", type: .send)
        peripheral.writeValue(data, for: writeCharacteristics, type: .withResponse)
    }
}
