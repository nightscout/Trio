//
//  GlucoseInfo.swift
//  LibreTransmitter
//
//  Created by LoopKit Authors on 02/07/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit

public class GlucoseInfo: ObservableObject, Equatable, Hashable {

    @Published public var glucose: HKQuantity?
    @Published public var date: Date?
    @Published public var checksum = ""
    // @Published var entryErrors = ""

    @Published public var prediction: HKQuantity?
    @Published public var predictionDate: Date?

    public static func ==(lhs: GlucoseInfo, rhs: GlucoseInfo) -> Bool {
         lhs.glucose == rhs.glucose && lhs.date == rhs.date &&
         lhs.checksum == rhs.checksum && lhs.prediction == rhs.prediction && lhs.predictionDate == rhs.predictionDate

     }
}
