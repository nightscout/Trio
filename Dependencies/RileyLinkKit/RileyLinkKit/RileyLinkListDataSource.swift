//
//  RileyLinkListDataSource.swift
//  RileyLinkKit
//
//  Created by Pete Schwamb on 6/7/22.
//  Copyright © 2022 Pete Schwamb. All rights reserved.
//

import Foundation
import RileyLinkBLEKit
import SwiftUI

public class RileyLinkListDataSource: ObservableObject {

    public let rileyLinkPumpManager: RileyLinkPumpManager

    @Published private(set) public var devices: [RileyLinkDevice] = []

    public init(rileyLinkPumpManager: RileyLinkPumpManager) {
        self.rileyLinkPumpManager = rileyLinkPumpManager

        // Register for manager notifications
        NotificationCenter.default.addObserver(self, selector: #selector(reloadDevices), name: .ManagerDevicesDidChange, object: rileyLinkPumpManager.rileyLinkDeviceProvider)

        // Register for device notifications
        for name in [.DeviceConnectionStateDidChange, .DeviceRSSIDidChange, .DeviceNameDidChange] as [Notification.Name] {
            NotificationCenter.default.addObserver(self, selector: #selector(reloadDevices), name: name, object: nil)
        }

        reloadDevices()
    }

    public func autoconnectBinding(for device: RileyLinkDevice) -> Binding<Bool> {
        return Binding(
            get: { [weak self] in
                if let connectionManager = self?.rileyLinkPumpManager.rileyLinkDeviceProvider {
                    return connectionManager.shouldConnect(to: device.peripheralIdentifier.uuidString)
                } else {
                    return false
                }
            },
            set: { [weak self] in
                if $0 {
                    self?.rileyLinkPumpManager.connectToRileyLink(device)
                } else {
                    self?.rileyLinkPumpManager.disconnectFromRileyLink(device)
                }
            })
    }

    @objc private func reloadDevices() {
        rileyLinkPumpManager.rileyLinkDeviceProvider.getDevices { (devices) in
            DispatchQueue.main.async { [weak self] in
                self?.devices = devices
            }
        }
    }

    public var isScanningEnabled: Bool = false {
        didSet {
            rileyLinkPumpManager.rileyLinkDeviceProvider.setScanningEnabled(isScanningEnabled)

            if isScanningEnabled {
                rssiFetchTimer = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(updateRSSI), userInfo: nil, repeats: true)
                updateRSSI()
            } else {
                rssiFetchTimer = nil
            }
        }
    }

    var connecting: Bool {
        #if targetEnvironment(simulator)
        return true
        #else

        return rileyLinkPumpManager.rileyLinkDeviceProvider.connectingCount > 0
        #endif
    }


    private var rssiFetchTimer: Timer? {
        willSet {
            rssiFetchTimer?.invalidate()
        }
    }

    @objc public func updateRSSI() {
        for device in devices {
            device.readRSSI()
        }
    }
}
