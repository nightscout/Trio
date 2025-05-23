// Trio
// OverrideRunStored+helper.swift
// Created by Deniz Cengiz on 2025-04-21.

import CoreData
import Foundation

extension NSPredicate {
    static var overridesRunStoredFromOneDayAgo: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "startDate >= %@", date as NSDate)
    }
}
