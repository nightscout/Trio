//
//  RileyLinkDeviceTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/5/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import LoopKitUI
import RileyLinkBLEKit
import RileyLinkKit
import os.log

let CellIdentifier = "Cell"

public class RileyLinkSwitch: UISwitch {
    
    public var index: Int = 0
    public var section: Int = 0
}

public class RileyLinkCell: UITableViewCell {
    public let switchView = RileyLinkSwitch()
    
    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(switchView)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        switchView.frame = CGRect(x: frame.width - 51 - 20, y: (frame.height - 31) / 2, width: 51, height: 31)
    }
}

public class RileyLinkDeviceTableViewController: UITableViewController {

    private let log = OSLog(category: "RileyLinkDeviceTableViewController")

    public let device: RileyLinkDevice

    private var bleRSSI: Int?

    private var firmwareVersion: String? {
        didSet {
            guard isViewLoaded else {
                return
            }
            
            cellForRow(.version)?.detailTextLabel?.text = firmwareVersion
        }
    }
    
    private var uptime: TimeInterval? {
        didSet {
            guard isViewLoaded else {
                return
            }
            
            cellForRow(.uptime)?.setDetailAge(uptime)
        }
    }
    
    private var battery: Int? {
        didSet {
            guard isViewLoaded else {
                return
            }
            cellForRow(.battery)?.setDetailBatteryLevel(battery)
        }
    }
    
    private var frequency: Measurement<UnitFrequency>? {
        didSet {
            guard isViewLoaded else {
                return
            }
            
            cellForRow(.frequency)?.setDetailFrequency(frequency, formatter: frequencyFormatter)
        }
    }
    
    private var ledMode: RileyLinkLEDMode? {
        didSet {
            guard isViewLoaded else {
                return
            }
            cellForRow(.diagnosticLEDSMode)?.setLEDMode(ledMode)
        }
    }

    var rssiFetchTimer: Timer? {
        willSet {
            rssiFetchTimer?.invalidate()
        }
    }

    private var hasPiezo: Bool = false

    private var appeared = false
    
    private var batteryAlertLevel: Int? {
        didSet {
            batteryAlertLevelChanged?(batteryAlertLevel)
        }
    }
    
    private var batteryAlertLevelChanged: ((Int?) -> Void)?

    public init(device: RileyLinkDevice, batteryAlertLevel: Int?, batteryAlertLevelChanged: ((Int?) -> Void)? ) {
        self.device = device
        self.batteryAlertLevel = batteryAlertLevel
        self.batteryAlertLevelChanged = batteryAlertLevelChanged

        super.init(style: .grouped)

        updateDeviceStatus()

        NotificationCenter.default.addObserver(forName: .DeviceStatusUpdated, object: device, queue: .main)
        { (notification) in
            self.updateDeviceStatus()
        }
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = device.name
        
        switch device.hardwareType {
        case .riley, .none:
            deviceRows = [
                .customName,
                .version,
                .rssi,
                .connection,
                .uptime,
                .frequency
            ]
            
            sections = [
                .device,
                .rileyLinkCommands
            ]
        case .ema:
            deviceRows = [
                .customName,
                .version,
                .rssi,
                .connection,
                .uptime,
                .frequency,
                .battery
            ]

            sections = [
                .device,
                .alert,
                .rileyLinkCommands
            ]
        case .orange:
            deviceRows = [
                .customName,
                .version,
                .rssi,
                .connection,
                .uptime,
                .battery,
                .voltage
            ]
            
            if device.hasOrangeLinkService {
                sections = [
                    .device,
                    .alert,
                    .configureCommand,
                    .orangeLinkCommands
                ]
            } else {
                sections = [
                    .device
                ]
            }
        }
        
        self.observe()
    }
    
    @objc func updateRSSI() {
        device.readRSSI()
    }

    // This does not trigger any BLE reads; it just gets status from the device in a safe manner, and reloads the table
    func updateDeviceStatus() {
        device.getStatus { (status) in
            DispatchQueue.main.async {
                self.firmwareVersion = status.version
                self.ledOn = status.ledOn
                self.vibrationOn = status.vibrationOn
                self.voltage = status.voltage
                self.battery = status.battery
                self.hasPiezo = status.hasPiezo
                self.tableView.reloadData()
            }
        }
    }
    
    func updateUptime() {
        device.runSession(withName: "Get stats for uptime") { (session) in
            do {
                let statistics = try session.getRileyLinkStatistics()
                DispatchQueue.main.async {
                    self.uptime = statistics.uptime
                }
            } catch let error {
                self.log.error("Failed to get stats for uptime: %{public}@", String(describing: error))
            }
        }
    }
    
    func updateFrequency() {

        device.runSession(withName: "Get base frequency") { (session) in
            do {
                let frequency = try session.readBaseFrequency()
                DispatchQueue.main.async {
                    self.frequency = frequency
                }
            } catch let error {
                self.log.error("Failed to get base frequency: %{public}@", String(describing: error))
            }
        }
    }
    
    func readDiagnosticLEDMode() {
        device.readDiagnosticLEDModeForBLEChip(completion: { ledMode in
            DispatchQueue.main.async {
                self.ledMode = ledMode
            }
        })
    }

    // References to registered notification center observers
    private var notificationObservers: [Any] = []
    
    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func observe() {
        let center = NotificationCenter.default
        let mainQueue = OperationQueue.main
        
        notificationObservers = [
            center.addObserver(forName: .DeviceNameDidChange, object: device, queue: mainQueue) { [weak self] (note) -> Void in
            if let cell = self?.cellForRow(.customName) {
                cell.detailTextLabel?.text = self?.device.name
            }
            self?.title = self?.device.name
            self?.tableView.reloadData()
        },
            center.addObserver(forName: .DeviceConnectionStateDidChange, object: device, queue: mainQueue) { [weak self] (note) -> Void in
            if let cell = self?.cellForRow(.connection) {
                cell.detailTextLabel?.text = self?.device.peripheralState.description
            }
        },
            center.addObserver(forName: .DeviceRSSIDidChange, object: device, queue: mainQueue) { [weak self] (note) -> Void in
            self?.bleRSSI = note.userInfo?[RileyLinkBluetoothDevice.notificationRSSIKey] as? Int
            
            if let cell = self?.cellForRow(.rssi), let formatter = self?.integerFormatter {
                cell.setDetailRSSI(self?.bleRSSI, formatter: formatter)
            }
        },
            center.addObserver(forName: .DeviceDidStartIdle, object: device, queue: mainQueue) { [weak self] (note) in
            self?.updateDeviceStatus()
        },
            center.addObserver(forName: .DeviceStatusUpdated, object: device, queue: mainQueue) { [weak self] (note) in
            self?.updateDeviceStatus()
        },
        ]
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if appeared {
            tableView.reloadData()
        }
        
        rssiFetchTimer = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(updateRSSI), userInfo: nil, repeats: true)
        
        appeared = true
        
        updateRSSI()
        
        if deviceRows.contains(.frequency) {
            updateFrequency()
        }

        updateUptime()
        
        switch device.hardwareType {
        case .riley:
            readDiagnosticLEDMode()
        case .ema:
            device.updateBatteryLevel()
            readDiagnosticLEDMode()
        case .orange:
            device.updateBatteryLevel()
            device.orangeWritePwd()
            device.orangeReadSet()
            device.orangeReadVDC()
            device.orangeAction(.fw_hw)
        default:
            break
        }
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if redOn || yellowOn {
            device.orangeAction(.off)
        }
        
        if shakeOn {
            device.orangeAction(.shakeOff)
        }
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        rssiFetchTimer = nil
    }


    // MARK: - Formatters

    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()

        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .medium

        return dateFormatter
    }()
    
    private lazy var integerFormatter = NumberFormatter()

    private lazy var decimalFormatter: NumberFormatter = {
        let decimalFormatter = NumberFormatter()

        decimalFormatter.numberStyle = .decimal
        decimalFormatter.maximumFractionDigits = 2
        return decimalFormatter
    }()
    
    private lazy var frequencyFormatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.numberFormatter = decimalFormatter
        return formatter
    }()

    // MARK: - Table view data source

    private enum Section: Int, CaseIterable {
        case device
        case alert
        case configureCommand
        case orangeLinkCommands
        case rileyLinkCommands
    }
    
    private var sections: [Section] = []

    private enum AlertRow: Int, CaseIterable {
        case battery
    }

    private enum DeviceRow: Int, CaseIterable {
        case customName
        case version
        case rssi
        case connection
        case uptime
        case frequency
        case battery
        case voltage
    }
    
    private var deviceRows: [DeviceRow] = []
    
    private enum RileyLinkCommandRow: Int, CaseIterable {
        case diagnosticLEDSMode
        case getStatistics
    }

    private enum OrangeLinkCommandRow: Int, CaseIterable {
        case yellow
        case red
        case shake
        case findDevice
    }

    private enum OrangeConfigureCommandRow: Int, CaseIterable {
        case connectionLED
        case connectionVibrate
    }

    private func cellForRow(_ row: DeviceRow) -> UITableViewCell? {
        guard let rowIndex = deviceRows.firstIndex(of: row),
              let sectionIndex = sections.firstIndex(of: Section.device) else
        {
            return nil
        }
        return tableView.cellForRow(at: IndexPath(row: rowIndex, section: sectionIndex))
    }

    private func cellForRow(_ row: OrangeConfigureCommandRow) -> UITableViewCell? {
        guard let sectionIndex = sections.firstIndex(of: Section.orangeLinkCommands) else
        {
            return nil
        }
        return tableView.cellForRow(at: IndexPath(row: row.rawValue, section: sectionIndex))
    }

    private func cellForRow(_ row: OrangeLinkCommandRow) -> UITableViewCell? {
        guard let sectionIndex = sections.firstIndex(of: Section.orangeLinkCommands) else
        {
            return nil
        }
        return tableView.cellForRow(at: IndexPath(row: row.rawValue, section: sectionIndex))
    }
    
    private func cellForRow(_ row: RileyLinkCommandRow) -> UITableViewCell? {
        guard let sectionIndex = sections.firstIndex(of: Section.rileyLinkCommands) else
        {
            return nil
        }
        return tableView.cellForRow(at: IndexPath(row: row.rawValue, section: sectionIndex))
    }

    public override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard section < sections.count else {
            return 0
        }
        
        switch sections[section] {
        case .device:
            return deviceRows.count
        case .rileyLinkCommands:
            return RileyLinkCommandRow.allCases.count
        case .configureCommand:
            return OrangeConfigureCommandRow.allCases.count
        case .orangeLinkCommands:
            let count = OrangeLinkCommandRow.allCases.count
            return hasPiezo ? count : count-1
        case .alert:
            return AlertRow.allCases.count
        }
    }
    
    @objc
    func switchAction(sender: RileyLinkSwitch) {
        switch sections[sender.section] {
        case .orangeLinkCommands:
            switch OrangeLinkCommandRow(rawValue: sender.index)! {
            case .yellow:
                if sender.isOn {
                    device.orangeAction(.yellow)
                } else {
                    device.orangeAction(.off)
                }
                yellowOn = sender.isOn
                redOn = false
            case .red:
                if sender.isOn {
                    device.orangeAction(.red)
                } else {
                    device.orangeAction(.off)
                }
                yellowOn = false
                redOn = sender.isOn
            case .shake:
                if sender.isOn {
                    device.orangeAction(.shake)
                } else {
                    device.orangeAction(.shakeOff)
                }
                shakeOn = sender.isOn
            default:
                break
            }
        case .configureCommand:
            switch OrangeConfigureCommandRow(rawValue: sender.index)! {
            case .connectionLED:
                device.setOrangeConfig(.connectionLED, isOn: sender.isOn)
                ledOn = sender.isOn
            case .connectionVibrate:
                device.setOrangeConfig(.connectionVibrate, isOn: sender.isOn)
                vibrationOn = sender.isOn
            }
        default:
            break
        }
        tableView.reloadData()
    }
    
    var yellowOn = false
    var redOn = false
    var shakeOn = false
    private var ledOn: Bool = false
    private var vibrationOn: Bool = false
    var voltage: Float?

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: RileyLinkCell

        if let reusableCell = tableView.dequeueReusableCell(withIdentifier: CellIdentifier) as? RileyLinkCell {
            cell = reusableCell
        } else {
            cell = RileyLinkCell(style: .value1, reuseIdentifier: CellIdentifier)
            cell.switchView.addTarget(self, action: #selector(switchAction(sender:)), for: .valueChanged)
        }
        
        let switchView = cell.switchView
        switchView.isHidden = true
        switchView.index = indexPath.row
        switchView.section = indexPath.section
        
        cell.accessoryType = .none
        cell.detailTextLabel?.text = nil

        switch sections[indexPath.section] {
        case .device:
            switch deviceRows[indexPath.row] {
            case .customName:
                cell.textLabel?.text = LocalizedString("Name", comment: "The title of the cell showing device name")
                cell.detailTextLabel?.text = device.name
                cell.accessoryType = .disclosureIndicator
            case .version:
                cell.textLabel?.text = LocalizedString("Firmware", comment: "The title of the cell showing firmware version")
                cell.detailTextLabel?.text = firmwareVersion
            case .connection:
                cell.textLabel?.text = LocalizedString("Connection State", comment: "The title of the cell showing BLE connection state")
                cell.detailTextLabel?.text = device.peripheralState.description
            case .rssi:
                cell.textLabel?.text = LocalizedString("Signal Strength", comment: "The title of the cell showing BLE signal strength (RSSI)")
                cell.setDetailRSSI(bleRSSI, formatter: integerFormatter)
            case .uptime:
                cell.textLabel?.text = LocalizedString("Uptime", comment: "The title of the cell showing uptime")
                cell.setDetailAge(uptime)
            case .frequency:
                cell.textLabel?.text = LocalizedString("Frequency", comment: "The title of the cell showing current rileylink frequency")
                cell.setDetailFrequency(frequency, formatter: frequencyFormatter)
            case .battery:
                cell.textLabel?.text = LocalizedString("Battery level", comment: "The title of the cell showing battery level")
                cell.setDetailBatteryLevel(battery)
            case .voltage:
                cell.textLabel?.text = LocalizedString("Voltage", comment: "The title of the cell showing ORL")
                cell.setVoltage(voltage)
            }
        case .alert:
            switch AlertRow(rawValue: indexPath.row)! {
            case .battery:
                cell.accessoryType = .disclosureIndicator
                cell.textLabel?.text = LocalizedString("Low Battery Alert", comment: "The title of the cell showing battery level")
                cell.setBatteryAlert(batteryAlertLevel, formatter: integerFormatter)
            }
        case .rileyLinkCommands:
            switch RileyLinkCommandRow(rawValue: indexPath.row)! {
            case .diagnosticLEDSMode:
                cell.textLabel?.text = LocalizedString("Toggle Diagnostic LEDs", comment: "The title of the command to update diagnostic LEDs")
                cell.setLEDMode(ledMode)
            case .getStatistics:
                cell.textLabel?.text = LocalizedString("Get RileyLink Statistics", comment: "The title of the command to fetch RileyLink statistics")
            }
        case .orangeLinkCommands:
            cell.accessoryType = .disclosureIndicator
            cell.detailTextLabel?.text = nil
            
            switch OrangeLinkCommandRow(rawValue: indexPath.row)! {
            case .yellow:
                switchView.isHidden = false
                cell.accessoryType = .none
                switchView.isOn = yellowOn
                cell.textLabel?.text = LocalizedString("Lighten Yellow LED", comment: "The title of the cell showing Lighten Yellow LED")
            case .red:
                switchView.isHidden = false
                cell.accessoryType = .none
                switchView.isOn = redOn
                cell.textLabel?.text = LocalizedString("Lighten Red LED", comment: "The title of the cell showing Lighten Red LED")
            case .shake:
                switchView.isHidden = false
                switchView.isOn = shakeOn
                cell.accessoryType = .none
                cell.textLabel?.text = LocalizedString("Test Vibration", comment: "The title of the cell showing Test Vibration")
            case .findDevice:
                cell.textLabel?.text = LocalizedString("Find Device", comment: "The title of the cell for sounding device finding piezo")
                cell.detailTextLabel?.text = nil
            }
        case .configureCommand:
            switch OrangeConfigureCommandRow(rawValue: indexPath.row)! {
            case .connectionLED:
                switchView.isHidden = false
                switchView.isOn = ledOn
                cell.accessoryType = .none
                cell.textLabel?.text = LocalizedString("Connection LED", comment: "The title of the cell for connection LED")
            case .connectionVibrate:
                switchView.isHidden = false
                switchView.isOn = vibrationOn
                cell.accessoryType = .none
                cell.textLabel?.text = LocalizedString("Connection Vibration", comment: "The title of the cell for connection vibration")
            }
        }

        return cell
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sections[section] {
        case .device:
            return LocalizedString("Device", comment: "The title of the section describing the device")
        case .rileyLinkCommands:
            return LocalizedString("Test Commands", comment: "The title of the section for rileylink commands")
        case .orangeLinkCommands:
            return LocalizedString("Test Commands", comment: "The title of the section for orangelink commands")
        case .configureCommand:
            return LocalizedString("Connection Monitoring", comment: "The title of the section for connection monitoring")
        case .alert:
            return LocalizedString("Alert", comment: "The title of the section for alerts")
        }
    }

    // MARK: - UITableViewDelegate

    public override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        switch sections[indexPath.section] {
        case .device:
            switch deviceRows[indexPath.row] {
            case .customName:
                return true
            default:
                return false
            }
        case .configureCommand:
            return false
        case .orangeLinkCommands:
            switch OrangeLinkCommandRow(rawValue: indexPath.row)! {
            case .findDevice:
                return true
            default:
                return false
            }
        case .rileyLinkCommands:
            return device.isConnected
        case .alert:
            return true
        }
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch sections[indexPath.section] {
        case .device:
            switch deviceRows[indexPath.row] {
            case .customName:
                let vc = TextFieldTableViewController()
                if let cell = tableView.cellForRow(at: indexPath) {
                    vc.title = cell.textLabel?.text
                    vc.value = device.name
                    vc.delegate = self
                    vc.keyboardType = .default
                }

                show(vc, sender: indexPath)
            default:
                break
            }
        case .rileyLinkCommands:
            var vc: CommandResponseViewController?

            switch RileyLinkCommandRow(rawValue: indexPath.row)! {
            case .diagnosticLEDSMode:
                let nextMode: RileyLinkLEDMode
                switch ledMode {
                case.on:
                    nextMode = .off
                default:
                    nextMode = .on
                }
                vc = .setDiagnosticLEDMode(device: device, mode: nextMode)
            case .getStatistics:
                vc = .getStatistics(device: device)
            }
            if let cell = tableView.cellForRow(at: indexPath) {
                vc?.title = cell.textLabel?.text
            }

            if let vc = vc {
                show(vc, sender: indexPath)
            }

        case .orangeLinkCommands:
            switch OrangeLinkCommandRow(rawValue: indexPath.row)! {
            case .findDevice:
                device.findDevice()
                tableView.deselectRow(at: indexPath, animated: true)
            default:
                break
            }
        case .configureCommand:
            break
        case .alert:
            switch AlertRow(rawValue: indexPath.row)! {
            case .battery:
                let alert = UIAlertController.init(title: "Battery level Alert", message: nil, preferredStyle: .actionSheet)
                let action = UIAlertAction.init(title: "OFF", style: .default) { _ in
                    self.batteryAlertLevel = nil
                    self.tableView.reloadData()
                }
                alert.addAction(action)

                for value in [20,30,40,50] {
                    let action = UIAlertAction.init(title: "\(value)%", style: .default) { _ in
                        self.batteryAlertLevel = value
                        self.tableView.reloadData()
                    }
                    alert.addAction(action)
                }
                present(alert, animated: true, completion: nil)
            }
        }
    }
}


extension RileyLinkDeviceTableViewController: TextFieldTableViewControllerDelegate {
    public func textFieldTableViewControllerDidReturn(_ controller: TextFieldTableViewController) {
        _ = navigationController?.popViewController(animated: true)
    }

    public func textFieldTableViewControllerDidEndEditing(_ controller: TextFieldTableViewController) {
        if let indexPath = tableView.indexPathForSelectedRow {
            switch sections[indexPath.section] {
            case .device:
                switch deviceRows[indexPath.row] {
                case .customName:
                    device.setCustomName(controller.value!)
                default:
                    break
                }
            default:
                break
            }
        }
    }
}

private extension TimeInterval {
    func format(using units: NSCalendar.Unit) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = units
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropLeading
        formatter.maximumUnitCount = 2
        
        return formatter.string(from: self)
    }
}

private extension UITableViewCell {
    func setDetailDate(_ date: Date?, formatter: DateFormatter) {
        if let date = date {
            detailTextLabel?.text = formatter.string(from: date)
        } else {
            detailTextLabel?.text = "-"
        }
    }

    func setDetailRSSI(_ decibles: Int?, formatter: NumberFormatter) {
        detailTextLabel?.text = formatter.decibleString(from: decibles) ?? "-"
    }
    
    func setDetailAge(_ age: TimeInterval?) {
        if let age = age {
            detailTextLabel?.text = age.format(using: [.day, .hour, .minute])
        } else {
            detailTextLabel?.text = ""
        }
    }
    
    func setDetailBatteryLevel(_ batteryLevel: Int?) {
        if let batteryLevel = batteryLevel {
            detailTextLabel?.text = "\(batteryLevel)" + " %"
        } else {
            detailTextLabel?.text = ""
        }
    }
    
    func setDetailFrequency(_ frequency: Measurement<UnitFrequency>?, formatter: MeasurementFormatter) {
        if let frequency = frequency {
            detailTextLabel?.text = formatter.string(from: frequency)
        } else {
            detailTextLabel?.text = ""
        }
    }
    
    func setLEDMode(_ mode: RileyLinkLEDMode?) {
        switch mode {
        case .on:
            detailTextLabel?.text = LocalizedString("On", comment: "Text indicating LED Mode is on")
        case .off:
            detailTextLabel?.text = LocalizedString("Off", comment: "Text indicating LED Mode is off")
        case .auto:
            detailTextLabel?.text = LocalizedString("Auto", comment: "Text indicating LED Mode is auto")
        case .none:
            detailTextLabel?.text = ""
        }
    }
    
    func setVoltage(_ voltage: Float?) {
        if let voltage = voltage {
            detailTextLabel?.text = String(format: "%.1f%", voltage)
        } else {
            detailTextLabel?.text = ""
        }
    }
    
    func setBatteryAlert(_ level: Int?, formatter: NumberFormatter) {
        detailTextLabel?.text = formatter.percentString(from: level) ?? LocalizedString("Off", comment: "Detail text when battery alert disabled.")
    }
}
