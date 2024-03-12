//
//  MainViewController.swift
//  RileyLink
//
//  Created by Pete Schwamb on 5/11/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//
import UIKit
import SwiftUI
import MinimedKit
import MinimedKitUI
import RileyLinkBLEKit
import RileyLinkKit
import RileyLinkKitUI
import LoopKit
import LoopKitUI
import OmniKitUI

class MainViewController: RileyLinkSettingsViewController {
    
    let deviceDataManager: DeviceDataManager
    
    let insulinTintColor: Color
    
    let guidanceColors: GuidanceColors

    init(deviceDataManager: DeviceDataManager, insulinTintColor: Color, guidanceColors: GuidanceColors) {
        self.deviceDataManager = deviceDataManager
        self.insulinTintColor = insulinTintColor
        self.guidanceColors = guidanceColors
        let rileyLinkPumpManager = RileyLinkPumpManager(rileyLinkDeviceProvider: deviceDataManager.rileyLinkConnectionManager.deviceProvider, rileyLinkConnectionManager: deviceDataManager.rileyLinkConnectionManager)

        super.init(rileyLinkPumpManager: rileyLinkPumpManager, devicesSectionIndex: Section.rileyLinks.rawValue, style: .grouped)
        
        self.title = LocalizedString("RileyLink Testing", comment: "Title for RileyLink Testing main view controller")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.backgroundColor = UIColor.white
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
        
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 55
        
        tableView.register(TextButtonTableViewCell.self, forCellReuseIdentifier: TextButtonTableViewCell.className)
        tableView.register(SettingsImageTableViewCell.self, forCellReuseIdentifier: SettingsImageTableViewCell.className)
        
        let rlImage = UIImage(named: "RileyLink", in: Bundle.main, compatibleWith: tableView.traitCollection)
        let imageView = UIImageView(image: rlImage)
        imageView.tintColor = UIColor.white
        imageView.contentMode = .center
        imageView.frame.size.height += 30  // feels right
        imageView.backgroundColor = UIColor(named: "RileyLink Tint", in: Bundle.main, compatibleWith: tableView.traitCollection)
        tableView.tableHeaderView = imageView

        tableView.register(RileyLinkDeviceTableViewCell.self, forCellReuseIdentifier: RileyLinkDeviceTableViewCell.className)
        
        NotificationCenter.default.addObserver(self, selector: #selector(deviceConnectionStateDidChange), name: .DeviceConnectionStateDidChange, object: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        // Manually invoke the delegate for rows deselecting on appear
        for indexPath in tableView.indexPathsForSelectedRows ?? [] {
            _ = tableView(tableView, willDeselectRowAt: indexPath)
        }
        
        super.viewWillAppear(animated)
    }
    
    fileprivate enum Section: Int, CaseCountable {
        case rileyLinks = 0
        case pump
    }
    
    fileprivate enum PumpActionRow: Int, CaseCountable {
        case addMinimedPump = 0
        case setupOmnipod
    }
    
    weak var rileyLinkManager: RileyLinkBluetoothDeviceProvider!
    
    @objc private func deviceConnectionStateDidChange() {
        DispatchQueue.main.async {
            self.tableView.reloadSections(IndexSet([Section.pump.rawValue]), with: .none)
        }
    }
    
    private var shouldAllowAddingPump: Bool {
        return rileyLinkManager.connectingCount > 0
    }

    // MARK: Data Source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .rileyLinks:
            return super.tableView(tableView, numberOfRowsInSection: section)
        case .pump:
            if let _ = deviceDataManager.pumpManager {
                return 1
            } else {
                return PumpActionRow.count
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell
        
        switch(Section(rawValue: indexPath.section)!) {
        case .rileyLinks:
            return super.tableView(tableView, cellForRowAt: indexPath)
        case .pump:
            if let pumpManager = deviceDataManager.pumpManager {
                cell = tableView.dequeueReusableCell(withIdentifier: SettingsImageTableViewCell.className, for: indexPath)
                cell.imageView?.image = pumpManager.smallImage
                cell.textLabel?.text = pumpManager.localizedTitle
                cell.detailTextLabel?.text = nil
                cell.accessoryType = .disclosureIndicator
            } else {
                switch(PumpActionRow(rawValue: indexPath.row)!) {
                case .addMinimedPump:
                    cell = tableView.dequeueReusableCell(withIdentifier: TextButtonTableViewCell.className, for: indexPath)
                    let textButtonCell = cell as? TextButtonTableViewCell
                    textButtonCell?.isEnabled = shouldAllowAddingPump
                    textButtonCell?.isUserInteractionEnabled = shouldAllowAddingPump
                    cell.textLabel?.text = LocalizedString("Add Minimed Pump", comment: "Title text for button to set up a new minimed pump")
                case .setupOmnipod:
                    cell = tableView.dequeueReusableCell(withIdentifier: TextButtonTableViewCell.className, for: indexPath)
                    let textButtonCell = cell as? TextButtonTableViewCell
                    textButtonCell?.isEnabled = shouldAllowAddingPump
                    textButtonCell?.isUserInteractionEnabled = shouldAllowAddingPump
                    cell.textLabel?.text = LocalizedString("Setup Omnipod", comment: "Title text for button to set up omnipod")
                }
            }
        }
        return cell
    }
    
    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .rileyLinks:
            return super.tableView(tableView, titleForHeaderInSection: section)
        case .pump:
            return LocalizedString("Pumps", comment: "Title text for section listing configured pumps")
        }
    }
    
    public override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch Section(rawValue: section)! {
        case .rileyLinks:
            return super.tableView(tableView, viewForHeaderInSection: section)
        case .pump:
            return nil
        }
    }
    
    public override func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
        return devicesDataSource.tableView(tableView, estimatedHeightForHeaderInSection: section)
    }
    
    // MARK: - UITableViewDelegate
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .rileyLinks:
            let device = devicesDataSource.devices[indexPath.row]
            let vc = RileyLinkDeviceTableViewController(device: device, batteryAlertLevel: nil, batteryAlertLevelChanged: nil)
            show(vc, sender: indexPath)
        case .pump:
            if let pumpManager = deviceDataManager.pumpManager {
                var settings = pumpManager.settingsViewController(insulinTintColor: insulinTintColor, guidanceColors: guidanceColors)
                settings.completionDelegate = self
                present(settings, animated: true)
            } else {
                var setupViewController: UIViewController & PumpManagerOnboarding & CompletionNotifying
                switch PumpActionRow(rawValue: indexPath.row)! {
                case .addMinimedPump:
                    setupViewController = UIStoryboard(name: "MinimedPumpManager", bundle: Bundle(for: MinimedPumpManagerSetupViewController.self)).instantiateViewController(withIdentifier: "DevelopmentPumpSetup") as! MinimedPumpManagerSetupViewController
                case .setupOmnipod:
                    setupViewController = UIStoryboard(name: "OmnipodPumpManager", bundle: Bundle(for: OmnipodPumpManagerSetupViewController.self)).instantiateViewController(withIdentifier: "DevelopmentPumpSetup") as! OmnipodPumpManagerSetupViewController
                }
                if let rileyLinkManagerViewController = setupViewController as? RileyLinkManagerSetupViewController {
                    rileyLinkManagerViewController.rileyLinkPumpManager = RileyLinkPumpManager(rileyLinkDeviceProvider: deviceDataManager.rileyLinkConnectionManager.deviceProvider)
                }
                setupViewController.setupDelegate = self
                setupViewController.completionDelegate = self
                present(setupViewController, animated: true, completion: nil)
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, willDeselectRowAt indexPath: IndexPath) -> IndexPath? {
        switch Section(rawValue: indexPath.section)! {
        case .rileyLinks:
            break
        case .pump:
            tableView.reloadSections(IndexSet([Section.pump.rawValue]), with: .none)
        }
        
        return indexPath
    }
}

extension MainViewController: CompletionDelegate {
    func completionNotifyingDidComplete(_ object: CompletionNotifying) {
        if let vc = object as? UIViewController, presentedViewController === vc {
            dismiss(animated: true, completion: nil)
        }
    }
}

extension MainViewController: PumpManagerCreateDelegate {
    func pumpManagerOnboarding(_ notifying: PumpManagerCreateNotifying, didCreatePumpManager pumpManager: PumpManagerUI) {
        deviceDataManager.pumpManager = pumpManager
    }
}

extension MainViewController: PumpManagerOnboardingDelegate {
    func pumpManagerOnboarding(_ notifying: PumpManagerOnboarding, didOnboardPumpManager pumpManager: PumpManagerUI, withSettings settings: PumpManagerSetupSettings) {
        show(pumpManager.settingsViewController(insulinTintColor: insulinTintColor, guidanceColors: guidanceColors), sender: nil)
        tableView.reloadSections(IndexSet([Section.pump.rawValue]), with: .none)
    }
}
