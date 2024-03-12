//
//  RileyLinkSetupTableViewController.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKit
import LoopKitUI
import RileyLinkKit
import RileyLinkBLEKit

public class RileyLinkSetupTableViewController: SetupTableViewController {

    let rileyLinkPumpManager: RileyLinkPumpManager

    private lazy var devicesDataSource: RileyLinkDevicesTableViewDataSource = {
        return RileyLinkDevicesTableViewDataSource(
            rileyLinkPumpManager: rileyLinkPumpManager,
            devicesSectionIndex: Section.devices.rawValue
        )
    }()
    
    public required init?(coder aDecoder: NSCoder) {
        let deviceProvider = RileyLinkBluetoothDeviceProvider(autoConnectIDs: [])
        rileyLinkPumpManager = RileyLinkPumpManager(rileyLinkDeviceProvider: deviceProvider)
        super.init(coder: aDecoder)
    }


    public override func viewDidLoad() {
        super.viewDidLoad()

        devicesDataSource.tableView = tableView

        tableView.register(SetupImageTableViewCell.nib(), forCellReuseIdentifier: SetupImageTableViewCell.className)

        NotificationCenter.default.addObserver(self, selector: #selector(deviceConnectionStateDidChange), name: .DeviceConnectionStateDidChange, object: nil)

        updateContinueButtonState()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        devicesDataSource.isScanningEnabled = true
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        devicesDataSource.isScanningEnabled = false
    }

    // MARK: - Table view data source

    private enum Section: Int {
        case info
        case devices

        static let count = 2
    }

    private enum InfoRow: Int {
        case image
        case description

        static let count = 2
    }

    public override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.count
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .info:
            return InfoRow.count
        case .devices:
            return devicesDataSource.tableView(tableView, numberOfRowsInSection: section)
        }
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .info:
            switch InfoRow(rawValue: indexPath.row)! {
            case .image:
                let cell = tableView.dequeueReusableCell(withIdentifier: SetupImageTableViewCell.className, for: indexPath) as! SetupImageTableViewCell
                let bundle = Bundle(for: type(of: self))
                cell.mainImageView?.image = UIImage(named: "RileyLink", in: bundle, compatibleWith: cell.traitCollection)
                cell.mainImageView?.tintColor = UIColor(named: "RileyLink Tint", in: bundle, compatibleWith: cell.traitCollection)
                if #available(iOSApplicationExtension 13.0, *) {
                    cell.backgroundColor = .systemBackground
                }
                return cell
            case .description:
                var cell = tableView.dequeueReusableCell(withIdentifier: "DescriptionCell")
                if cell == nil {
                    cell = UITableViewCell(style: .default, reuseIdentifier: "DescriptionCell")
                    cell?.selectionStyle = .none
                    cell?.textLabel?.text = LocalizedString("RileyLink allows for communication with the pump over Bluetooth Low Energy.", comment: "RileyLink setup description")
                    cell?.textLabel?.numberOfLines = 0

                    if #available(iOSApplicationExtension 13.0, *) {
                        cell?.backgroundColor = .systemBackground
                    }
                }
                return cell!
            }
        case .devices:
            return devicesDataSource.tableView(tableView, cellForRowAt: indexPath)
        }
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .info:
            return nil
        case .devices:
            return devicesDataSource.tableView(tableView, titleForHeaderInSection: section)
        }
    }

    public override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch Section(rawValue: section)! {
        case .info:
            return nil
        case .devices:
            return devicesDataSource.tableView(tableView, viewForHeaderInSection: section)
        }
    }

    public override func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
        return devicesDataSource.tableView(tableView, estimatedHeightForHeaderInSection: section)
    }

    public override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return false
    }

    // MARK: - Navigation

    private var shouldContinue: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return rileyLinkPumpManager.rileyLinkDeviceProvider.connectingCount > 0
        #endif
    }

    @objc private func deviceConnectionStateDidChange() {
        DispatchQueue.main.async {
            self.updateContinueButtonState()
        }
    }

    private func updateContinueButtonState() {
        footerView.primaryButton.isEnabled = shouldContinue
    }

    public override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        return shouldContinue
    }

}
