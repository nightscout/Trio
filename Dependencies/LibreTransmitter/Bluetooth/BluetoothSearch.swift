//
//  BluetoothSearch.swift
//  MiaomiaoClientUI
//
//  Created by LoopKit Authors on 26/07/2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import CoreBluetooth
import Foundation
import OSLog
import UIKit

import Combine

public struct RSSIInfo {
    public let bledeviceID: String
    public let signalStrength: Int

    public var totalBars: Int {
        3
    }

    public var signalBars: Int {
        if signalStrength < -80 {
            return 1  // near
        }

        if signalStrength > -50 {
            return 3 // immediate
        }

        return 2 // near
    }

}

public protocol BluetoothSearcher {
    func disconnectManually()
    func scanForCompatibleDevices()
    func stopTimer()

    var passThroughMetaData: PassthroughSubject<(PeripheralProtocol, [String: Any]), Never> { get }
    var throttledRSSI: GenericThrottler<RSSIInfo, String> { get }
}


public final class BluetoothSearchManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, BluetoothSearcher {

    var centralManager: CBCentralManager!

    fileprivate lazy var logger = Logger(forType: Self.self)

    private var discoveredDevices = [CBPeripheral]()

    public let passThroughMetaData = PassthroughSubject<(PeripheralProtocol, [String: Any]), Never>()
    public let throttledRSSI = GenericThrottler(identificator: \RSSIInfo.bledeviceID, interval: 5)

    private var rescanTimerBag = Set<AnyCancellable>()

    public func addDiscoveredDevice(_ device: CBPeripheral, with metadata: [String: Any], rssi: Int) {
        passThroughMetaData.send((device, metadata))
        throttledRSSI.incoming.send(RSSIInfo(bledeviceID: device.identifier.uuidString, signalStrength: rssi))
    }

    public override init() {
        super.init()
        // calling readrssi on a peripheral is only supported on connected peripherals
        // here we want the AllowDuplicatesKey to be true so that we get a continous feed of new rssi values for
        // discovered but unconnected peripherals
        // This should work, but in practice, most devices will still only be discovered once, meaning that we cannot update rssi values
        // without either a new scan, or connecting to the peripheral and using .readrssi()
        // centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
        centralManager = CBCentralManager(delegate: self, queue: nil, options: nil)
        //        slipBuffer.delegate = self
        logger.debug("BluetoothSearchManager init called ")

        // Ugly hack to be able to update rssi continously without connecting to peripheral
        // Yes, this consumes extra power, but this feature is very convenient when needed, but very rarely used (only during setup)
        // startTimer()
    }

    public func startTimer() {
        stopTimer()

        Timer.publish(every: 10, on: .main, in: .default)
        .autoconnect()
        .sink(
            receiveValue: { [weak self ] _ in
                self?.rescan()
            }
        )
        .store(in: &rescanTimerBag)
    }

    public func stopTimer() {
        if !rescanTimerBag.isEmpty {
            rescanTimerBag.forEach { cancel in
                cancel.cancel()
            }
        }
    }

    func rescan() {
        if centralManager.isScanning {
            centralManager.stopScan()
        }
        logger.debug("Rescanning")

        self.scanForCompatibleDevices()
    }

    public func scanForCompatibleDevices() {

        if centralManager.state == .poweredOn && !centralManager.isScanning {
            logger.debug("Before scan for transmitter while central manager state \(String(describing: self.centralManager.state.rawValue))")

            // nil because mioamiao1 not advertising its services
            centralManager.scanForPeripherals(withServices: nil, options: nil)

            // Ugly hack to be able to update rssi continously without connecting to peripheral
            // Yes, this consumes extra power, but this feature is very convenient when needed, but very rarely used (only during setup)
            startTimer()
        }
    }

    public func disconnectManually() {
        logger.debug("did disconnect manually")
        if centralManager.isScanning {
            centralManager.stopScan()
        }
    }

    // MARK: - CBCentralManagerDelegate

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.debug("Central Manager did update state to \(String(describing: central.state.rawValue))")
        switch central.state {
        case .poweredOff, .resetting, .unauthorized, .unknown, .unsupported:
            logger.debug("Central Manager was either .poweredOff, .resetting, .unauthorized, .unknown, .unsupported: \(String(describing: central.state))")
        case .poweredOn:
            // we don't want this to start scanning right away, but rather wait until the view has appeared
            // this means that the view is responsible for calling scanForCompatibleDevices it self
            //scanForCompatibleDevices() // power was switched on, while app is running -> reconnect.
            break

        @unknown default:
            fatalError("libre bluetooth state unhandled")
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name?.lowercased() else {
            logger.debug("could not find name for device \(peripheral.identifier.uuidString)")
            return
        }

        if LibreTransmitters.isSupported(peripheral) {
            logger.debug("did recognize device: \(name): \(peripheral.identifier)")
            self.addDiscoveredDevice(peripheral, with: advertisementData, rssi: RSSI.intValue)
            // peripheral.delegate = self
            // peripheral.readRSSI()
        } else {
            if UserDefaults.standard.dangerModeActivated {
                // allow listing any device when danger mode is active

                let name = String(describing: peripheral.name)

                logger.debug("did add unknown device due to dangermode being active \(name): \(peripheral.identifier)")
                self.addDiscoveredDevice(peripheral, with: advertisementData, rssi: RSSI.intValue)
                // peripheral.delegate = self
                // peripheral.readRSSI()

            } else {
                logger.debug("did not add unknown device: \(name): \(peripheral.identifier)")
            }
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // self.lastConnectedIdentifier = peripheral.identifier.uuidString

    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.error("did fail to connect")
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.debug("did didDisconnectPeripheral")
    }

    // MARK: - CBPeripheralDelegate

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        logger.debug("Did discover services")
        if let error {
            logger.error("Did discover services error: \(error.localizedDescription)")
        }

        if let services = peripheral.services {
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)

                logger.debug("Did discover service: \(String(describing: service.debugDescription))")
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        logger.debug("Did discover characteristics for service \(String(describing: peripheral.name))")

        if let error {
            logger.error("Did discover characteristics for service error: \(error.localizedDescription)")
        }

        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                logger.debug("Did discover characteristic: \(String(describing: characteristic.debugDescription))")

                if (characteristic.properties.intersection(.notify)) == .notify && characteristic.uuid == CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") {
                    peripheral.setNotifyValue(true, for: characteristic)
                    logger.debug("Set notify value for this characteristic")
                }
                if characteristic.uuid == CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") {
                    // writeCharacteristic = characteristic
                }
            }
        } else {
            logger.error("Discovered characteristics, but no characteristics listed. There must be some error.")
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {

        // throttledRSSI.incoming.send(RSSIInfo(bledeviceID: peripheral.identifier.uuidString, signalStrength: RSSI.intValue))

        // peripheral.readRSSI() //we keep contuing to update the rssi (only works if peripheral is already connected....

    }
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        logger.debug("Did update notification state for characteristic: \(String(describing: characteristic.debugDescription))")
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        logger.debug("Did update value for characteristic: \(String(describing: characteristic.debugDescription))")
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        logger.debug("Did Write value \(String(characteristic.value.debugDescription)) for characteristic \(String(characteristic.debugDescription))")
    }

    deinit {
        logger.debug("BluetoothSearchManager deinit called")
    }
}
