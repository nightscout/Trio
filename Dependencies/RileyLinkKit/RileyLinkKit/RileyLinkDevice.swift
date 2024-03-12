//
//  RileyLinkDevice.swift
//  RileyLinkKit
//
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import RileyLinkBLEKit

extension Notification.Name {
    public static let DeviceRadioConfigDidChange = Notification.Name(rawValue: "com.rileylink.RileyLinkKit.DeviceRadioConfigDidChange")

    public static let DeviceStateDidChange = Notification.Name(rawValue: "com.rileylink.RileyLinkKit.DeviceStateDidChange")
}
