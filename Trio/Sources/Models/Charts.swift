//
// Trio
// Charts.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Jon B Mårtensson.
//
// Documentation available under: https://triodocs.org/

import Foundation

struct ShapeModel: Identifiable {
    var type: String
    var percent: Decimal
    var id = UUID()
}

struct ChartData: Identifiable {
    var date: Date
    var iob: Double
    var zt: Double
    var cob: Double
    var uam: Double
    var id = UUID()
}
