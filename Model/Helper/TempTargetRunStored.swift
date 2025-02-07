//
//  TempTargetRunStored.swift
//  Trio
//
//  Created by Marvin Polscheit on 15.11.24.
//
import CoreData

extension NSPredicate {
    static var tempTargetRunStoredFromOneDayAgo: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "startDate >= %@", date as NSDate)
    }
}
