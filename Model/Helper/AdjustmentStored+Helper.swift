//
// Trio
// AdjustmentStored+Helper.swift
// Created by Robert on 2025-02-08.
// Last edited by Robert on 2025-02-08.
// Most contributions by Robert.
//
// Documentation available under: https://triodocs.org/

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
