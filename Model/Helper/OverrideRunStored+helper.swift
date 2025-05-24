//
// Trio
// OverrideRunStored+helper.swift
// Created by Marvin Polscheit on 2024-11-16.
// Last edited by Marvin Polscheit on 2024-11-16.
// Most contributions by Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

import CoreData
import Foundation

extension NSPredicate {
    static var overridesRunStoredFromOneDayAgo: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "startDate >= %@", date as NSDate)
    }
}
