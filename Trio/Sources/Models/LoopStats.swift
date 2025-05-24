//
// Trio
// LoopStats.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Jon B Mårtensson and Jon Mårtensson.
//
// Documentation available under: https://triodocs.org/

import Foundation

struct LoopStats: JSON, Equatable {
    var start: Date
    var end: Date?
    var duration: Double?
    var loopStatus: String
    var interval: Double?

    init(
        start: Date,
        loopStatus: String,
        interval: Double?
    ) {
        self.start = start
        self.loopStatus = loopStatus
        self.interval = interval
    }
}

extension LoopStats {
    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case duration
        case loopStatus
        case interval
    }
}
