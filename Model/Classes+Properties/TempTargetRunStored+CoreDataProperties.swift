//
// Trio
// TempTargetRunStored+CoreDataProperties.swift
// Created by Deniz Cengiz on 2025-01-05.
// Last edited by Robert on 2025-02-07.
// Most contributions by Deniz Cengiz and Robert.
//
// Documentation available under: https://triodocs.org/

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
