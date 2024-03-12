//
//  MockSensorData.swift
//  LibreTransmitter
//
//  Created by Pete Schwamb on 6/27/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation

public struct MockSensorData: SensorDataProtocol {
    public var minutesSinceStart: Int

    public var maxMinutesWearTime: Int

    public var state: SensorState

    public var serialNumber: String

    public var footerCrc: UInt16

    public var date: Date

    public init(minutesSinceStart: Int, maxMinutesWearTime: Int, state: SensorState, serialNumber: String, footerCrc: UInt16, date: Date) {
        self.minutesSinceStart = minutesSinceStart
        self.maxMinutesWearTime = maxMinutesWearTime
        self.state = state
        self.serialNumber = serialNumber
        self.footerCrc = footerCrc
        self.date = date
    }
}
