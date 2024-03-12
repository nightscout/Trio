//
//  NumberFormatter.swift
//  RileyLink
//
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import Foundation

extension NumberFormatter {
    func decibleString(from decibles: Int?) -> String? {
        if let decibles = decibles, let formatted = string(from: NSNumber(value: decibles)) {
            return String(format: LocalizedString("%@ dB", comment: "Unit format string for an RSSI value in decibles"), formatted)
        } else {
            return nil
        }
    }

    func percentString(from percent: Int?) -> String? {
        if let percent = percent, let formatted = string(from: NSNumber(value: percent)) {
            return String(format: LocalizedString("%@%%", comment: "Unit format string for an value in percent"), formatted)
        } else {
            return nil
        }
    }

    func string(from number: Double) -> String? {
        return string(from: NSNumber(value: number))
    }
}
