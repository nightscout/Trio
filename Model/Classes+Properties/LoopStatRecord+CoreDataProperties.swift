//
// Trio
// LoopStatRecord+CoreDataProperties.swift
// Created by Deniz Cengiz on 2024-09-11.
// Last edited by Deniz Cengiz on 2024-09-11.
// Most contributions by Deniz Cengiz and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

import CoreData
import Foundation

public extension LoopStatRecord {
    @nonobjc class func fetchRequest() -> NSFetchRequest<LoopStatRecord> {
        NSFetchRequest<LoopStatRecord>(entityName: "LoopStatRecord")
    }

    @NSManaged var duration: Double
    @NSManaged var end: Date?
    @NSManaged var interval: Double
    @NSManaged var loopStatus: String?
    @NSManaged var start: Date?
}

extension LoopStatRecord: Identifiable {}
