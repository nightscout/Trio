//
//  WatchGlucoseObject.swift
//  Trio
//
//  Created by Cengiz Deniz on 23.01.25.
//
import Foundation

struct WatchGlucoseObject: Hashable, Equatable, Codable {
    let date: Date
    /// mg/dL
    let glucose: Int
    /// 0xRRGGBB under the dynamic color scheme, as the phone computes it; nil under the static one.
    var color: Int? = nil
}
