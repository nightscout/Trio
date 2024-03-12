//
//  RileyLinkDeviceProvider.swift
//  RileyLinkBLEKit
//
//  Created by Pete Schwamb on 9/5/22.
//  Copyright © 2022 Pete Schwamb. All rights reserved.
//

import Foundation

public protocol RileyLinkDeviceProviderDelegate : AnyObject {
    func rileylinkDeviceProvider(_ rileylinkDeviceProvider: RileyLinkDeviceProvider, didChange state: RileyLinkConnectionState)
}

public protocol RileyLinkDeviceProvider: AnyObject {
    typealias RawStateValue = [String : Any]

    var delegate: RileyLinkDeviceProviderDelegate? { get set }

    var idleListeningState: RileyLinkBluetoothDevice.IdleListeningState { get set }
    var idleListeningEnabled: Bool { get }
    var timerTickEnabled: Bool { get set }
    var connectingCount: Int { get }

    func deprioritize(_ device: RileyLinkDevice, completion: (() -> Void)?)
    func assertIdleListening(forcingRestart: Bool)
    func getDevices(_ completion: @escaping (_ devices: [RileyLinkDevice]) -> Void)
    func connect(_ device: RileyLinkDevice)
    func disconnect(_ device: RileyLinkDevice)
    func setScanningEnabled(_ enabled: Bool)
    func shouldConnect(to deviceID: String) -> Bool

    var debugDescription: String { get }
}
