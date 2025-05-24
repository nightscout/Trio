//
// Trio
// HealthKitSample.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Jon B.M.
//
// Documentation available under: https://triodocs.org/

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
