// Trio
// OverrideRunStored+CoreDataProperties.swift
// Created by polscm32 on 2024-07-01.

import CoreData
import Foundation

public extension OverrideRunStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<OverrideRunStored> {
        NSFetchRequest<OverrideRunStored>(entityName: "OverrideRunStored")
    }

    @NSManaged var endDate: Date?
    @NSManaged var id: UUID?
    @NSManaged var isUploadedToNS: Bool
    @NSManaged var name: String?
    @NSManaged var startDate: Date?
    @NSManaged var target: NSDecimalNumber?
    @NSManaged var override: OverrideStored?
}

extension OverrideRunStored: Identifiable {}
