//
//  ConcreteSensorDisplayable.swift
//  MiaomiaoClient
//
//  Created by LoopKit Authors on 04/11/2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit

public struct ConcreteGlucoseDisplayable: GlucoseDisplayable {
    public var glucoseRangeCategory: GlucoseRangeCategory?

    public var isStateValid: Bool

    public var trendType: GlucoseTrend?

    public var isLocal: Bool

    // public var batteries : [(name: String, percentage: Int)]?

    public var trendRate: HKQuantity? { nil }
}
