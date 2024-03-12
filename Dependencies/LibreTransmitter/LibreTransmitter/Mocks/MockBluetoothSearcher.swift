//
//  MockBluetoothSearcher.swift
//  LibreDemoPlugin
//
//  Created by Pete Schwamb on 6/24/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import os.log
import Combine
import CoreBluetooth

public struct MockBluetoothSearcher: BluetoothSearcher {
    fileprivate lazy var logger = Logger(forType: Self.self)

    public let throttledRSSI = GenericThrottler(identificator: \RSSIInfo.bledeviceID, interval: 5)
    public let passThroughMetaData = PassthroughSubject<(PeripheralProtocol, [String: Any]), Never>()

    public init() {
    }

    public func disconnectManually() {
        print("Mock searcher disconnecting")
    }

    public func scanForCompatibleDevices() {
        print("Mock searcher scanning")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            for device in mockData {
                passThroughMetaData.send((device, [:]))
            }
        }
    }

    public func stopTimer() {
        print("Mock searcher stop timer")
    }

    var mockData: [PeripheralProtocol] {
        [
            MockedPeripheral(name: "miaomiaoMockTransmitter"),
            MockedPeripheral(name: "bubbleMockTransmitter"),
            MockedPeripheral(name: "abbottMockSensor"),
        ]
    }
}

public class MockedPeripheral: PeripheralProtocol, Identifiable {
    public var name: String?

    public var name2: String {
        name ?? "unknown-device"
    }

    public var asStringIdentifier: String {
        name2
    }

    public init(name: String) {
        self.name = name
    }
}

