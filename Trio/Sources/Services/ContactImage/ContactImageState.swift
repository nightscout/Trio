//
// Trio
// ContactImageState.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Marc R Kellerman and Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import Foundation

struct ContactImageState: Codable {
    var glucose: String?
    var trend: String?
    var delta: String?
    var lastLoopDate: Date?
    var iob: Decimal?
    var iobText: String?
    var cob: Decimal?
    var cobText: String?
    var eventualBG: String?
    var maxIOB: Decimal = 10.0
    var maxCOB: Decimal = 120.0
    var highGlucoseColorValue: Decimal = 180.0
    var lowGlucoseColorValue: Decimal = 70.0
    var glucoseColorScheme: GlucoseColorScheme = .staticColor
    var targetGlucose: Decimal = 100.0
}
