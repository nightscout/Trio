//
//  LibreTransmitter.swift
//  MiaomiaoClient
//
//  Created by LoopKit Authors on 08/01/2020.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import CoreBluetooth
import Foundation
import UIKit
public protocol LibreTransmitterProxyProtocol: AnyObject {
    static var shortTransmitterName: String { get }
    static var smallImage: UIImage? { get }
    static var manufacturerer: String { get }
    static var requiresPhoneNFC: Bool { get }
    static var requiresSetup: Bool { get }
    static func canSupportPeripheral(_ peripheral: PeripheralProtocol) -> Bool

    static var writeCharacteristic: UUIDContainer? { get set }
    static var notifyCharacteristic: UUIDContainer? { get set }
    static var serviceUUID: [UUIDContainer] { get set }

    var delegate: LibreTransmitterDelegate? { get set }
    init(delegate: LibreTransmitterDelegate, advertisementData: [String: Any]? )
    func requestData(writeCharacteristics: CBCharacteristic, peripheral: CBPeripheral)
    func updateValueForNotifyCharacteristics(_ value: Data, peripheral: CBPeripheral, writeCharacteristic: CBCharacteristic?)
    func didDiscoverWriteCharacteristics(_ peripheral: CBPeripheral, writeCharacteristics: CBCharacteristic)
    func didDiscoverNotificationCharacteristic(_ peripheral: CBPeripheral, notifyCharacteristic: CBCharacteristic)
    func didWrite(_ peripheral: CBPeripheral, characteristics: CBCharacteristic)

    func reset()

    static func getDeviceDetailsFromAdvertisement(advertisementData: [String: Any]?) -> String?

}

extension LibreTransmitterProxyProtocol {
    func canSupportPeripheral(_ peripheral: PeripheralProtocol) -> Bool {
        Self.canSupportPeripheral(peripheral)
    }
    public var staticType: LibreTransmitterProxyProtocol.Type {
        Self.self
    }

    func didDiscoverWriteCharacteristics(_ peripheral: CBPeripheral, writeCharacteristics: CBCharacteristic) {

    }

    func didDiscoverNotificationCharacteristic(_ peripheral: CBPeripheral, notifyCharacteristic: CBCharacteristic) {
        print("Setting setNotifyValue on notifyCharacteristic")
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
    }

    func didWrite(_ peripheral: CBPeripheral, characteristics: CBCharacteristic) {

    }

    static var requiresSetup: Bool { return false}
    static var requiresPhoneNFC: Bool { return false }

    static var requiresDelayedReconnect: Bool { return false}
}

extension Array where Array.Element == LibreTransmitterProxyProtocol.Type {
    func getServicesForDiscovery() -> [CBUUID] {
        self.flatMap {
            return $0.serviceUUID.map { $0.value }
        }.removingDuplicates()
    }
}

public enum LibreTransmitters {
    public static var all: [LibreTransmitterProxyProtocol.Type] {
        [MiaoMiaoTransmitter.self, BubbleTransmitter.self, Libre2DirectTransmitter.self]
    }
    public static func isSupported(_ peripheral: CBPeripheral) -> Bool {
        getSupportedPlugins(peripheral)?.isEmpty == false
    }

    public static func getSupportedPlugins(_ peripheral: PeripheralProtocol) -> [LibreTransmitterProxyProtocol.Type]? {
        all.enumerated().compactMap {
            $0.element.canSupportPeripheral(peripheral) ? $0.element : nil
        }
    }
}
