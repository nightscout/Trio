//
//  SettingsTableViewController.swift
//  RileyLink
//
//  Created by Nathan Racklyeft on 8/29/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import UIKit
import RileyLinkKit

private let ConfigCellIdentifier = "ConfigTableViewCell"

private let TapToSetString = NSLocalizedString("Tap to set", comment: "The empty-state text for a configuration value")

class SettingsTableViewController: UITableViewController, TextFieldTableViewControllerDelegate {

    private enum Section: Int {
        case About = 0
        case Upload
        case Configuration

        static let count = 3
    }
    
    private enum AboutRow: Int {
        case Version = 0
        
        static let count = 1
    }

    private enum UploadRow: Int {
        case Upload = 0

        static let count = 1
    }

    private enum ConfigurationRow: Int {
        case PumpID = 0
        case Nightscout
        static let count = 2
    }
    
    private var dataManager: DeviceDataManager {
        return DeviceDataManager.sharedManager
    }

    // MARK: - UITableViewDataSource

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return Section.count
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .About:
            return AboutRow.count
        case .Upload:
            return UploadRow.count
        case .Configuration:
            return ConfigurationRow.count
        }
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell: UITableViewCell

        switch Section(rawValue: indexPath.section)! {
        case .About:
            switch AboutRow(rawValue: indexPath.row)! {
            case .Version:
                let versionCell = UITableViewCell(style: .Default, reuseIdentifier: "Version")
                versionCell.selectionStyle = .None
                let version = NSBundle.mainBundle().objectForInfoDictionaryKey("CFBundleShortVersionString")!
                versionCell.textLabel?.text = "RileyLink iOS v\(version)"
                
                return versionCell
            }
        case .Upload:
            switch UploadRow(rawValue: indexPath.row)! {
            case .Upload:
                let switchCell = tableView.dequeueReusableCellWithIdentifier(SwitchTableViewCell.className, forIndexPath: indexPath) as! SwitchTableViewCell

                switchCell.`switch`?.on = Config.sharedInstance().uploadEnabled
                switchCell.titleLabel.text = NSLocalizedString("Upload To Nightscout", comment: "The title text for the nightscout upload enabled switch cell")
                switchCell.`switch`?.addTarget(self, action: #selector(uploadEnabledChanged(_:)), forControlEvents: .ValueChanged)
                
                return switchCell
            }
        case .Configuration:
            let configCell = tableView.dequeueReusableCellWithIdentifier(ConfigCellIdentifier, forIndexPath: indexPath)

            switch ConfigurationRow(rawValue: indexPath.row)! {
            case .PumpID:
                configCell.textLabel?.text = NSLocalizedString("Pump ID", comment: "The title text for the pump ID config value")
                configCell.detailTextLabel?.text = DeviceDataManager.sharedManager.pumpID ?? TapToSetString
            case .Nightscout:
                let nightscoutService = dataManager.remoteDataManager.nightscoutService
                
                configCell.textLabel?.text = nightscoutService.title
                configCell.detailTextLabel?.text = nightscoutService.siteURL?.absoluteString ?? TapToSetString
            }
            cell = configCell
        }
        return cell
    }

    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .About:
            return NSLocalizedString("About", comment: "The title of the about section")
        case .Upload:
            return nil
        case .Configuration:
            return NSLocalizedString("Configuration", comment: "The title of the configuration section in settings")
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .Configuration:
            let sender = tableView.cellForRowAtIndexPath(indexPath)

            switch ConfigurationRow(rawValue: indexPath.row)! {
            case .PumpID:
                performSegueWithIdentifier(TextFieldTableViewController.className, sender: sender)
            case .Nightscout:
                let service = dataManager.remoteDataManager.nightscoutService
                let vc = AuthenticationViewController(authentication: service)
                vc.authenticationObserver = { [unowned self] (service) in
                    self.dataManager.remoteDataManager.nightscoutService = service
                    
                    self.tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: .None)
                }
                
                showViewController(vc, sender: indexPath)
            }
        case .Upload, .About:
            break
        }
    }

    override func tableView(tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch Section(rawValue: section)! {
        case .Upload, .Configuration, .About:
            return nil
        }
    }

    // MARK: - Navigation

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if let
            cell = sender as? UITableViewCell,
            indexPath = tableView.indexPathForCell(cell)
        {
            switch segue.destinationViewController {
            case let vc as TextFieldTableViewController:
                switch ConfigurationRow(rawValue: indexPath.row)! {
                case .PumpID:
                    vc.placeholder = NSLocalizedString("Enter the 6-digit pump ID", comment: "The placeholder text instructing users how to enter a pump ID")
                    vc.value = DeviceDataManager.sharedManager.pumpID
                default:
                    break
                }
                
                vc.title = cell.textLabel?.text
                vc.indexPath = indexPath
                vc.delegate = self
            default:
                break
            }
        }
    }

    // MARK: - Uploader mangement

    func uploadEnabledChanged(sender: UISwitch) {
        Config.sharedInstance().uploadEnabled = sender.on
    }

    // MARK: - TextFieldTableViewControllerDelegate

    func textFieldTableViewControllerDidEndEditing(controller: TextFieldTableViewController) {
        if let indexPath = controller.indexPath {
            switch ConfigurationRow(rawValue: indexPath.row)! {
            case .PumpID:
                DeviceDataManager.sharedManager.pumpID = controller.value
            default:
                break
            }
        }

        tableView.reloadData()
    }

}
