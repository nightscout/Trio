// DiaconnBLEManager.swift
// G8 펌프 BLE 연결 및 통신 처리

import CoreBluetooth
import Foundation

class DiaconnBLEManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var centralManager: CBCentralManager!
    var peripheral: CBPeripheral?

    let serviceUUID = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9e")
    let writeUUID = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9e")
    let notifyUUID = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9e")

    var writeChar: CBCharacteristic?
    var notifyChar: CBCharacteristic?
    var isConnected = false

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func connect() {
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            print("Bluetooth is not powered on")
        } else {
            connect()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        print("Discovered: \(peripheral.name ?? "Unknown")")
        self.peripheral = peripheral
        self.peripheral?.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral.name ?? "Unknown")")
        isConnected = true
        peripheral.discoverServices(nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            if char.uuid == writeUUID {
                writeChar = char
            } else if char.uuid == notifyUUID {
                notifyChar = char
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value else { return }
        print("Received data: \(value as NSData)")
        // 여기에서 응답 파싱 가능
    }

    func send(_ data: Data) {
        guard let peripheral = peripheral, let writeChar = writeChar else { return }
        peripheral.writeValue(data, for: writeChar, type: .withoutResponse)
    }

    func disconnect() {
        guard let peripheral = peripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
        isConnected = false
    }
}
