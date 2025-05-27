//
// Trio
// WatchGlucoseObject.swift
// Created by Deniz Cengiz on 2025-01-23.
// Last edited by Deniz Cengiz on 2025-01-23.
// Most contributions by Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import Foundation

struct WatchGlucoseObject: Hashable, Equatable, Codable {
    let date: Date
    let glucose: Double
    let color: String
}
