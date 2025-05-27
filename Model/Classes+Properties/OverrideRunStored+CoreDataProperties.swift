//
// Trio
// OverrideRunStored+CoreDataProperties.swift
// Created by Deniz Cengiz on 2024-09-11.
// Last edited by Deniz Cengiz on 2024-09-11.
// Most contributions by Deniz Cengiz and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

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
