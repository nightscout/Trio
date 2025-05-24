//
// Trio
// TempTargetRunStored.swift
// Created by Marvin Polscheit on 2024-11-16.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Marvin Polscheit and Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import CoreData

extension NSPredicate {
    static var tempTargetRunStoredFromOneDayAgo: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "startDate >= %@", date as NSDate)
    }
}
