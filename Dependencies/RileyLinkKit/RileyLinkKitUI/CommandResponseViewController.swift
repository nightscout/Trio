//
//  CommandResponseViewController.swift
//  RileyLinkKitUI
//
//  Created by Pete Schwamb on 7/19/21.
//  Copyright © 2021 Pete Schwamb. All rights reserved.
//

import Foundation
import LoopKitUI
import RileyLinkBLEKit

extension CommandResponseViewController {
    typealias T = CommandResponseViewController
    
    static func getStatistics(device: RileyLinkDevice) -> T {
        return T { (completionHandler) -> String in
            device.runSession(withName: "Get Statistics") { session in
                let response: String

                do {
                    let stats = try session.getRileyLinkStatistics()
                    response = String(describing: stats)
                } catch let error {
                    response = String(describing: error)
                }

                DispatchQueue.main.async {
                    completionHandler(response)
                }
            }
            
            return LocalizedString("Get Statistics…", comment: "Progress message for getting statistics.")
        }
    }
    
    static func setDiagnosticLEDMode(device: RileyLinkDevice, mode: RileyLinkLEDMode) -> T {
        return T { (completionHandler) -> String in
            device.setDiagnosticeLEDModeForBLEChip(mode)
            device.runSession(withName: "Update diagnostic LED mode") { session in
                let response: String
                do {
                    try session.setCCLEDMode(mode)
                    switch mode {
                    case .on:
                        response = "Diagnostic mode enabled"
                    default:
                        response = "Diagnostic mode disabled"
                    }
                } catch let error {
                    response = String(describing: error)
                }

                DispatchQueue.main.async {
                    completionHandler(response)
                }
            }

            return LocalizedString("Updating diagnostic LEDs mode", comment: "Progress message for changing diagnostic LED mode")
        }
    }
}
