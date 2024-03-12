//
//  RileyLinkSettingsViewController.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import UIKit
import CoreBluetooth
import RileyLinkBLEKit
import RileyLinkKit


open class RileyLinkSettingsViewController: UITableViewController {

    public let devicesDataSource: RileyLinkDevicesTableViewDataSource

    public init(rileyLinkPumpManager: RileyLinkPumpManager, devicesSectionIndex: Int, style: UITableView.Style) {
        devicesDataSource = RileyLinkDevicesTableViewDataSource(rileyLinkPumpManager: rileyLinkPumpManager, devicesSectionIndex: devicesSectionIndex)
        super.init(style: style)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override open func viewDidLoad() {
        super.viewDidLoad()

        devicesDataSource.tableView = tableView
    }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        devicesDataSource.isScanningEnabled = true
    }

    override open func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        devicesDataSource.isScanningEnabled = false
    }

    // MARK: - UITableViewDataSource

    override open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return devicesDataSource.tableView(tableView, numberOfRowsInSection: section)
    }

    override open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return devicesDataSource.tableView(tableView, cellForRowAt: indexPath)
    }

    override open func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return devicesDataSource.tableView(tableView, titleForHeaderInSection: section)
    }

    // MARK: - UITableViewDelegate

    override open func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return devicesDataSource.tableView(tableView, viewForHeaderInSection: section)
    }
}
