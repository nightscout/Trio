//
//  RileyLinkListTableViewController.swift
//  RileyLink
//
//  Created by Pete Schwamb on 5/11/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import UIKit
import RileyLinkKit

class RileyLinkListTableViewController: UITableViewController {
    
    // Retreive the managedObjectContext from AppDelegate
    let managedObjectContext = (UIApplication.sharedApplication().delegate as! AppDelegate).managedObjectContext
    
    override func viewDidLoad() {
      super.viewDidLoad()

        tableView.registerNib(RileyLinkDeviceTableViewCell.nib(), forCellReuseIdentifier: RileyLinkDeviceTableViewCell.className)

        dataManagerObserver = NSNotificationCenter.defaultCenter().addObserverForName(nil, object: dataManager, queue: nil) { [weak self = self] (note) -> Void in
            if let deviceManager = self?.dataManager.rileyLinkManager {
                switch note.name {
                case RileyLinkDeviceManager.DidDiscoverDeviceNotification:
                    self?.tableView.insertRowsAtIndexPaths([NSIndexPath(forRow: deviceManager.devices.count - 1, inSection: 0)], withRowAnimation: .Automatic)
                case RileyLinkDeviceManager.ConnectionStateDidChangeNotification,
                     RileyLinkDeviceManager.RSSIDidChangeNotification,
                     RileyLinkDeviceManager.NameDidChangeNotification:
                    if let device = note.userInfo?[RileyLinkDeviceManager.RileyLinkDeviceKey] as? RileyLinkDevice, index = deviceManager.devices.indexOf({ $0 === device }) {
                        self?.tableView.reloadRowsAtIndexPaths([NSIndexPath(forRow: index, inSection: 0)], withRowAnimation: .None)
                    }
                default:
                    break
                }
            }
        }
    }
    
    deinit {
        dataManagerObserver = nil
    }
    
    private var dataManagerObserver: AnyObject? {
        willSet {
            if let observer = dataManagerObserver {
                NSNotificationCenter.defaultCenter().removeObserver(observer)
            }
        }
    }
    
    private var dataManager: DeviceDataManager {
        return DeviceDataManager.sharedManager
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        
        dataManager.rileyLinkManager.deviceScanningEnabled = true
    }

    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        
        dataManager.rileyLinkManager.deviceScanningEnabled = false
    }
    
    // MARK: Table view data source
    
    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dataManager.rileyLinkManager.devices.count
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell: UITableViewCell
        
        let deviceCell = tableView.dequeueReusableCellWithIdentifier(RileyLinkDeviceTableViewCell.className) as! RileyLinkDeviceTableViewCell
        
        let device = dataManager.rileyLinkManager.devices[indexPath.row]
        
        deviceCell.configureCellWithName(device.name,
                                         signal: device.RSSI,
                                         peripheralState: device.peripheral.state
        )
        
        deviceCell.connectSwitch.addTarget(self, action: #selector(deviceConnectionChanged(_:)), forControlEvents: .ValueChanged)
        
        cell = deviceCell
        return cell
    }
    
    func deviceConnectionChanged(connectSwitch: UISwitch) {
        let switchOrigin = connectSwitch.convertPoint(.zero, toView: tableView)
        
        if let indexPath = tableView.indexPathForRowAtPoint(switchOrigin)
        {
            let device = dataManager.rileyLinkManager.devices[indexPath.row]
            
            if connectSwitch.on {
                dataManager.connectToRileyLink(device)
            } else {
                dataManager.disconnectFromRileyLink(device)
            }
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        let vc = RileyLinkDeviceTableViewController()

        vc.device = dataManager.rileyLinkManager.devices[indexPath.row]

        showViewController(vc, sender: indexPath)
    }
    
    /*
     // Override to support conditional editing of the table view.
     - (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
     // Return NO if you do not want the specified item to be editable.
     return YES;
     }
     */
    
    /*
     // Override to support editing the table view.
     - (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
     if (editingStyle == UITableViewCellEditingStyleDelete) {
     // Delete the row from the data source
     [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
     } else if (editingStyle == UITableViewCellEditingStyleInsert) {
     // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
     }
     }
     */
    
    /*
     // Override to support rearranging the table view.
     - (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath {
     }
     */
    
    /*
     // Override to support conditional rearranging of the table view.
     - (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
     // Return NO if you do not want the item to be re-orderable.
     return YES;
     }
     */

}