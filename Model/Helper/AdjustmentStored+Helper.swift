// Trio
// AdjustmentStored+Helper.swift
// Created by Deniz Cengiz on 2025-04-21.

import CoreData
import Foundation

extension NSPredicate {
    static var lastActiveAdjustmentNotYetUploadedToNightscout: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(
            format: "date >= %@ AND enabled == %@ AND isUploadedToNS == %@",
            date as NSDate,
            true as NSNumber,
            false as NSNumber
        )
    }
}
