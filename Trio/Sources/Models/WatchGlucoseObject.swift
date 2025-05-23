// Trio
// WatchGlucoseObject.swift
// Created by Deniz Cengiz on 2025-04-21.

import Foundation

struct WatchGlucoseObject: Hashable, Equatable, Codable {
    let date: Date
    let glucose: Double
    let color: String
}
