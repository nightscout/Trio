//
//  TransmitterInfo.swift
//  LibreTransmitter
//
//  Created by LoopKit Authors on 02/07/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

public class TransmitterInfo: ObservableObject, Equatable, Hashable {
    @Published public var battery = ""
    @Published public var hardware = ""
    @Published public var firmware = ""
    @Published public var connectionState = ""
    @Published public var transmitterType = ""
    @Published public var transmitterMacAddress = ""
    @Published public var sensorType = ""

    public static func == (lhs: TransmitterInfo, rhs: TransmitterInfo) -> Bool {
         lhs.battery == rhs.battery && lhs.hardware == rhs.hardware &&
         lhs.firmware == rhs.firmware && lhs.connectionState == rhs.connectionState &&
         lhs.transmitterType == rhs.transmitterType && lhs.transmitterMacAddress == rhs.transmitterMacAddress &&
         lhs.sensorType == rhs.sensorType

     }

}
