//
//  MockSensorPairingService.swift
//  LibreDemoPlugin
//
//  Created by Pete Schwamb on 6/22/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import Combine
import os.log

public class MockSensorPairingService: SensorPairingProtocol {
    fileprivate lazy var logger = Logger(forType: Self.self)

    private var readingsSubject = PassthroughSubject<SensorPairingInfo, Never>()

    public var onCancel: (() -> Void)?

    public var publisher: AnyPublisher<SensorPairingInfo, Never> {
        readingsSubject.eraseToAnyPublisher()
    }

    public init() {
    }

    private func sendUpdate(_ info: SensorPairingInfo) {
        DispatchQueue.main.async { [weak self] in
            self?.readingsSubject.send(info)
        }
    }

    public func pairSensor() throws {
        let info = FakeSensorPairingData().fakeSensorPairingInfo()
        logger.debug("Sending fake sensor pairinginfo: \(info.description)")
        //delay a bit to simulate a real tag readout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.sendUpdate(info)
        }
    }
}
