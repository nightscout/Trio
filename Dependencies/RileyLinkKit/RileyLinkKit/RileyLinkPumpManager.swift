//
//  RileyLinkPumpManager.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import LoopKit
import RileyLinkBLEKit

open class RileyLinkPumpManager {

    open var rileyLinkConnectionManagerState: RileyLinkConnectionState?
    
    public init(rileyLinkDeviceProvider: RileyLinkDeviceProvider) {
        
        self.rileyLinkDeviceProvider = rileyLinkDeviceProvider

        rileyLinkDeviceProvider.delegate = self

        // Listen for device notifications
        NotificationCenter.default.addObserver(self, selector: #selector(receivedRileyLinkPacketNotification(_:)), name: .DevicePacketReceived, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(receivedRileyLinkTimerTickNotification(_:)), name: .DeviceTimerDidTick, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(receivedRileyLinkBatteryUpdate(_:)), name: .DeviceBatteryLevelUpdated, object: nil)

    }
    
    /// Access to rileylink devices
    public let rileyLinkDeviceProvider: RileyLinkDeviceProvider

    // TODO: Put this on each RileyLinkDevice?
    private var lastTimerTick = Locked(Date.distantPast)

    /// Called when one of the connected devices receives a packet outside of a session
    ///
    /// - Parameters:
    ///   - device: The device
    ///   - packet: The received packet
    open func device(_ device: RileyLinkDevice, didReceivePacket packet: RFPacket) { }

    open func deviceTimerDidTick(_ device: RileyLinkDevice) { }

    open func device(_ device: RileyLinkDevice, didUpdateBattery level: Int) { }

    // MARK: - CustomDebugStringConvertible
    
    open var debugDescription: String {
        return [
            "## RileyLinkPumpManager",
            "lastTimerTick: \(String(describing: lastTimerTick.value))",
            "",
            String(reflecting: rileyLinkDeviceProvider),
        ].joined(separator: "\n")
    }
}

// MARK: - RileyLink Updates
extension RileyLinkPumpManager {

    /**
     Called when a new idle message is received by the RileyLink.

     Only MySentryPumpStatus messages are handled.

     - parameter note: The notification object
     */
    @objc private func receivedRileyLinkPacketNotification(_ note: Notification) {
        guard let device = note.object as? RileyLinkDevice,
            let packet = note.userInfo?[RileyLinkBluetoothDevice.notificationPacketKey] as? RFPacket
        else {
            return
        }

        device.assertOnSessionQueue()

        self.device(device, didReceivePacket: packet)
    }


    @objc private func receivedRileyLinkTimerTickNotification(_ note: Notification) {
        guard let device = note.object as? RileyLinkDevice else {
            return
        }

        self.lastTimerTick.value = Date()
        self.deviceTimerDidTick(device)
    }
    

    @objc private func receivedRileyLinkBatteryUpdate(_ note: Notification) {
        guard let device = note.object as? RileyLinkDevice,
              let batteryLevel = note.userInfo?[RileyLinkBluetoothDevice.batteryLevelKey] as? Int
        else {
            return
        }

        device.assertOnSessionQueue()

        self.device(device, didUpdateBattery: batteryLevel)
    }
    
    
    public func connectToRileyLink(_ device: RileyLinkDevice) {
        rileyLinkDeviceProvider.connect(device)
    }

    public func disconnectFromRileyLink(_ device: RileyLinkDevice) {
        rileyLinkDeviceProvider.disconnect(device)
    }
    
}

extension RileyLinkPumpManager: RileyLinkDeviceProviderDelegate {
    public func rileylinkDeviceProvider(_ rileylinkDeviceProvider: RileyLinkBLEKit.RileyLinkDeviceProvider, didChange state: RileyLinkBLEKit.RileyLinkConnectionState) {
        self.rileyLinkConnectionManagerState = state
    }
}
