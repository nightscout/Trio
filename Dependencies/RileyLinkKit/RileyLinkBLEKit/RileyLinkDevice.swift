//
//  RileyLinkDevice.swift
//  RileyLinkBLEKit
//
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import CoreBluetooth

public enum RileyLinkHardwareType {
    case riley
    case orange
    case ema
    
    var monitorsBattery: Bool {
        if self == .riley {
            return false
        }
        return true
    }
}

public struct RileyLinkDeviceStatus {
    public let lastIdle: Date?
    public let name: String?
    public let version: String
    public let ledOn: Bool
    public let vibrationOn: Bool
    public let voltage: Float?
    public let battery: Int?
    public let hasPiezo: Bool

    public init(lastIdle: Date?, name: String?, version: String, ledOn: Bool, vibrationOn: Bool, voltage: Float?, battery: Int?, hasPiezo: Bool) {
        self.lastIdle = lastIdle
        self.name = name
        self.version = version
        self.ledOn = ledOn
        self.vibrationOn = vibrationOn
        self.voltage = voltage
        self.battery = battery
        self.hasPiezo = hasPiezo
    }
}


public protocol RileyLinkDevice {

    var isConnected: Bool { get }
    var rlFirmwareDescription: String { get }
    var hasOrangeLinkService: Bool { get }
    var hardwareType: RileyLinkHardwareType? { get }
    var rssi: Int? { get }

    var name: String? { get }
    var deviceURI: String { get }
    var peripheralIdentifier: UUID { get }
    var peripheralState: CBPeripheralState { get }

    func readRSSI()
    func setCustomName(_ name: String)

    func updateBatteryLevel()

    func orangeAction(_ command: OrangeLinkCommand)
    func setOrangeConfig(_ config: OrangeLinkConfigurationSetting, isOn: Bool)
    func orangeWritePwd()
    func orangeClose()
    func orangeReadSet()
    func orangeReadVDC()
    func findDevice()
    func setDiagnosticeLEDModeForBLEChip(_ mode: RileyLinkLEDMode)
    func readDiagnosticLEDModeForBLEChip(completion: @escaping (RileyLinkLEDMode?) -> Void)
    func assertOnSessionQueue()
    func sessionQueueAsyncAfter(deadline: DispatchTime, execute: @escaping () -> Void)

    func runSession(withName name: String, _ block: @escaping (_ session: CommandSession) -> Void)
    func getStatus(_ completion: @escaping (_ status: RileyLinkDeviceStatus) -> Void)
}

extension Array where Element == RileyLinkDevice {
    public var firstConnected: Element? {
        return self.first { (device) -> Bool in
            return device.isConnected
        }
    }
}

