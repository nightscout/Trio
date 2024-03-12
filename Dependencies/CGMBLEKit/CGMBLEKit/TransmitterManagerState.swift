//
//  TransmitterManagerState.swift
//  CGMBLEKit
//
//  Created by Pete Schwamb on 9/11/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

public struct TransmitterManagerState: RawRepresentable, Equatable {
    public typealias RawValue = CGMManager.RawStateValue

    public static let version = 1

    public var transmitterID: String

    public var passiveModeEnabled: Bool = true

    public var transmitterStartDate: Date?

    public var sensorStartOffset: UInt32?

    public var shouldSyncToRemoteService: Bool

    public init(
        transmitterID: String,
        shouldSyncToRemoteService: Bool = false,
        transmitterStartDate: Date? = nil,
        sensorStartOffset: UInt32? = nil
    ) {
        self.transmitterID = transmitterID
        self.shouldSyncToRemoteService = shouldSyncToRemoteService
        self.transmitterStartDate = transmitterStartDate
        self.sensorStartOffset = sensorStartOffset
    }

    public init?(rawValue: RawValue) {
        guard let transmitterID = rawValue["transmitterID"] as? String
        else {
            return nil
        }

        let shouldSyncToRemoteService = rawValue["shouldSyncToRemoteService"] as? Bool ?? false

        let transmitterStartDate = rawValue["transmitterStartDate"] as? Date

        let sensorStartOffset = rawValue["sensorStartOffset"] as? UInt32

        self.init(
            transmitterID: transmitterID,
            shouldSyncToRemoteService: shouldSyncToRemoteService,
            transmitterStartDate: transmitterStartDate,
            sensorStartOffset: sensorStartOffset
        )
    }

    public var rawValue: RawValue {
        var rval: RawValue = [
            "transmitterID": transmitterID,
            "shouldSyncToRemoteService": shouldSyncToRemoteService
        ]

        rval["transmitterStartDate"] = transmitterStartDate
        rval["sensorStartOffset"] = sensorStartOffset

        return rval
    }
}
