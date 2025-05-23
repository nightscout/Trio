// Trio
// TempTargetRunStored+CoreDataProperties.swift
// Created by Deniz Cengiz on 2025-04-21.

import CoreData
import Foundation

public extension TempTargetRunStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<TempTargetRunStored> {
        NSFetchRequest<TempTargetRunStored>(entityName: "TempTargetRunStored")
    }

    @NSManaged var endDate: Date?
    @NSManaged var id: UUID?
    @NSManaged var isUploadedToNS: Bool
    @NSManaged var name: String?
    @NSManaged var startDate: Date?
    @NSManaged var target: NSDecimalNumber?
    @NSManaged var tempTarget: TempTargetStored?
}

extension TempTargetRunStored: Identifiable {}
