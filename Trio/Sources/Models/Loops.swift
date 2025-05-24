//
// Trio
// Loops.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Jon Mårtensson.
//
// Documentation available under: https://triodocs.org/

import Foundation

struct Loops: JSON, Equatable {
    var loops: Int
    var errors: Int
    var success_rate: Decimal
    var avg_interval: Decimal
    var median_interval: Decimal
    var min_interval: Decimal
    var max_interval: Decimal
    var avg_duration: Decimal
    var median_duration: Decimal
    var min_duration: Decimal
    var max_duration: Decimal
}
