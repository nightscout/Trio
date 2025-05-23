// Trio
// HealthKitSample.swift
// Created by Jon B.M on 2021-12-05.

import Foundation

struct HealthKitSample: JSON, Hashable, Equatable {
    var healthKitId: String
    var date: Date
    var glucose: Int

    static func == (lhs: HealthKitSample, rhs: HealthKitSample) -> Bool {
        lhs.healthKitId == rhs.healthKitId
    }
}

extension HealthKitSample {
    private enum CodingKeys: String, CodingKey {
        case healthKitId = "healthkit_id"
        case date
        case glucose
    }
}
