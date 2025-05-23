// Trio
// TempTargetRunStored.swift
// Created by Deniz Cengiz on 2025-04-21.

import CoreData

extension NSPredicate {
    static var tempTargetRunStoredFromOneDayAgo: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "startDate >= %@", date as NSDate)
    }
}
