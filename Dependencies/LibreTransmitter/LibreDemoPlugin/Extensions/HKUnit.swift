//
//  HKUnit.swift
//  LibreDemoPlugin
//
//  Created by Pete Schwamb on 6/24/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation


import HealthKit

extension HKUnit {
    static let milligramsPerDeciliter: HKUnit = {
        HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
    }()
}
