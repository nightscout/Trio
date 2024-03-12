//
//  RileyLinkDevicesTableViewDataSource.swift
//  RileyLinkKitUI
//
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import UIKit
import CoreBluetooth
import RileyLinkBLEKit
import RileyLinkKit


public class RileyLinkDevicesTableViewDataSource: NSObject {
    public let rileyLinkPumpManager: RileyLinkPumpManager

    public var devicesSectionIndex: Int

    public var tableView: UITableView! {
        didSet {
            tableView.register(RileyLinkDeviceTableViewCell.self, forCellReuseIdentifier: RileyLinkDeviceTableViewCell.className)

            tableView.register(RileyLinkDevicesHeaderView.self, forHeaderFooterViewReuseIdentifier: RileyLinkDevicesHeaderView.className)

            // Register for manager notifications
            NotificationCenter.default.addObserver(self, selector: #selector(reloadDevices), name: .ManagerDevicesDidChange, object: rileyLinkPumpManager.rileyLinkDeviceProvider)

            // Register for device notifications
            for name in [.DeviceConnectionStateDidChange, .DeviceRSSIDidChange, .DeviceNameDidChange] as [Notification.Name] {
                NotificationCenter.default.addObserver(self, selector: #selector(deviceDidUpdate(_:)), name: name, object: nil)
            }

            reloadDevices()
        }
    }

    public init(rileyLinkPumpManager: RileyLinkPumpManager, devicesSectionIndex: Int) {
        self.rileyLinkPumpManager = rileyLinkPumpManager
        self.devicesSectionIndex = devicesSectionIndex
        super.init()
    }

    // MARK: -

    lazy var decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()

        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        return formatter
    }()

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

    private(set) public var devices: [RileyLinkDevice] = [] {
        didSet {
            // Assume only appends are possible when count changes for algorithmic simplicity
            guard oldValue.count < devices.count else {
                tableView.reloadSections(IndexSet(integer: devicesSectionIndex), with: .fade)
                return
            }

            tableView.beginUpdates()
    

            let insertedPaths = (oldValue.count..<devices.count).map { (index) -> IndexPath in
                return IndexPath(row: index, section: devicesSectionIndex)
            }
            tableView.insertRows(at: insertedPaths, with: .automatic)

            tableView.endUpdates()
        }
    }

    /// Returns an adjusted peripheral state reflecting the user's auto-connect preference.
    /// Peripherals connected to the system will show as disconnected if the user hasn't designated them
    ///
    /// - Parameter device: The peripheral
    /// - Returns: The adjusted connection state
    private func preferenceStateForDevice(_ device: RileyLinkDevice) -> CBPeripheralState? {
        let isAutoConnectDevice = rileyLinkPumpManager.rileyLinkDeviceProvider.shouldConnect(to: device.peripheralIdentifier.uuidString)
        var state = device.peripheralState

        switch state {
        case .disconnected, .disconnecting:
            break
        case .connecting, .connected:
            if !isAutoConnectDevice {
                state = .disconnected
            }
        @unknown default:
            break
        }

        return state
    }

    private var deviceRSSI: [UUID: Int] = [:]

    private var rssiFetchTimer: Timer? {
        willSet {
            rssiFetchTimer?.invalidate()
        }
    }

    @objc private func reloadDevices() {
        rileyLinkPumpManager.rileyLinkDeviceProvider.getDevices { (devices) in
            DispatchQueue.main.async { [weak self] in
                self?.devices = devices
            }
        }
    }

    @objc private func deviceDidUpdate(_ note: Notification) {
        DispatchQueue.main.async {
            if let device = note.object as? RileyLinkDevice, let index = self.devices.firstIndex(where: { $0.peripheralIdentifier == device.peripheralIdentifier }) {
                if let rssi = note.userInfo?[RileyLinkBluetoothDevice.notificationRSSIKey] as? Int {
                    self.deviceRSSI[device.peripheralIdentifier] = rssi
                }

                if let cell = self.tableView.cellForRow(at: IndexPath(row: index, section: self.devicesSectionIndex)) as? RileyLinkDeviceTableViewCell {
                    cell.configureCellWithName(
                        device.name,
                        signal: self.decimalFormatter.decibleString(from: self.deviceRSSI[device.peripheralIdentifier]),
                        peripheralState: self.preferenceStateForDevice(device)
                    )
                }
            }
        }
    }

    @objc public func updateRSSI() {
        for device in devices {
            device.readRSSI()
        }
    }

    @objc private func deviceConnectionChanged(_ connectSwitch: UISwitch) {
        let switchOrigin = connectSwitch.convert(CGPoint.zero, to: tableView)

        if let indexPath = tableView.indexPathForRow(at: switchOrigin), indexPath.section == devicesSectionIndex
        {
            let device = devices[indexPath.row]

            if connectSwitch.isOn {
                rileyLinkPumpManager.connectToRileyLink(device)
            } else {
                rileyLinkPumpManager.disconnectFromRileyLink(device)
            }
        }
    }
}

extension RileyLinkDevicesTableViewDataSource: UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return devices.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let deviceCell = tableView.dequeueReusableCell(withIdentifier: RileyLinkDeviceTableViewCell.className) as! RileyLinkDeviceTableViewCell
        let device = devices[indexPath.row]
        
        deviceCell.configureCellWithName(
            device.name,
            signal: decimalFormatter.decibleString(from: deviceRSSI[device.peripheralIdentifier]),
            peripheralState: self.preferenceStateForDevice(device)
        )

        deviceCell.connectSwitch?.addTarget(self, action: #selector(deviceConnectionChanged(_:)), for: .valueChanged)

        return deviceCell
    }

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return LocalizedString("Devices", comment: "The title of the devices table section in RileyLink settings")
    }
}

extension RileyLinkDevicesTableViewDataSource: UITableViewDelegate {
    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return tableView.dequeueReusableHeaderFooterView(withIdentifier: RileyLinkDevicesHeaderView.className)
    }

    public func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    public func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
        return 55
    }

    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return UITableView.automaticDimension
    }
}
