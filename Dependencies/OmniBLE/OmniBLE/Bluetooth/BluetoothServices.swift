//
//  BluetoothServices.swift
//  OmniBLE
//
//  Created by Randall Knutson on 11/01/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import CoreBluetooth

protocol CBUUIDRawValue: RawRepresentable {}
extension CBUUIDRawValue where RawValue == String {
    var cbUUID: CBUUID {
        return CBUUID(string: rawValue)
    }
}

enum PodCommand: UInt8 {
    case RTS = 0x00
    case CTS = 0x01
    case NACK = 0x02
    case ABORT = 0x03
    case SUCCESS = 0x04
    case FAIL = 0x05
    case HELLO = 0x06
    case INCORRECT = 0x09
}

enum OmnipodServiceUUID: String, CBUUIDRawValue {
    case advertisement = "00004024-0000-1000-8000-00805f9b34fb"
    case service = "1A7E4024-E3ED-4464-8B7E-751E03D0DC5F"
}

enum OmnipodCharacteristicUUID: String, CBUUIDRawValue {
    case command = "1A7E2441-E3ED-4464-8B7E-751E03D0DC5F"
    case data = "1A7E2442-E3ED-4464-8B7E-751E03D0DC5F"
}

extension PeripheralManager.Configuration {
    static var omnipod: PeripheralManager.Configuration {
        return PeripheralManager.Configuration(
            serviceCharacteristics: [
                OmnipodServiceUUID.service.cbUUID: [
                    OmnipodCharacteristicUUID.command.cbUUID,
                    OmnipodCharacteristicUUID.data.cbUUID,
                ]
            ],
            notifyingCharacteristics: [
                OmnipodServiceUUID.service.cbUUID: [
//                    OmnipodCharacteristicUUID.command.cbUUID,
//                    OmnipodCharacteristicUUID.data.cbUUID,
                ]
            ],
            valueUpdateMacros: [
                OmnipodCharacteristicUUID.command.cbUUID: { (manager: PeripheralManager) in
                    guard let characteristic = manager.peripheral.getCommandCharacteristic() else { return }
                    guard let value = characteristic.value else { return }

                    manager.queueLock.lock()
                    manager.cmdQueue.append(value)
                    manager.queueLock.signal()
                    manager.queueLock.unlock()
                },
                OmnipodCharacteristicUUID.data.cbUUID: { (manager: PeripheralManager) in
                    guard let characteristic = manager.peripheral.getDataCharacteristic() else { return }
                    guard let value = characteristic.value else { return }

                    manager.queueLock.lock()
                    manager.dataQueue.append(value)
                    manager.queueLock.signal()
                    manager.queueLock.unlock()
                }
            ]
        )
    }
}
