//
//  WatchGlucoseObject.swift
//  Trio
//
//  Created by Cengiz Deniz on 23.01.25.
//
import Foundation

struct WatchGlucoseObject: Hashable, Equatable, Codable {
    let date: Date
    let glucose: Double
    let color: String
}
