//
//  NotificationHelperOverride.swift
//  LibreTransmitter
//
//  Created by Bjørn Inge Berg on 16/01/2023.
//  Copyright © 2023 Mark Wilson. All rights reserved.
//

import Foundation
enum NotificationHelperOverride {
    static var shouldOverrideRequestCriticalPermissions : Bool {
        // if you want LibreTransmitter to try upgrading to critical notifications, change this
        false
    }
}
