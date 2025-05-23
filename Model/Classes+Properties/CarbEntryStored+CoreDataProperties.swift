// Trio
// CarbEntryStored+CoreDataProperties.swift
// Created by polscm32 on 2024-04-20.

import CoreData
import Foundation

public extension CarbEntryStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CarbEntryStored> {
        NSFetchRequest<CarbEntryStored>(entityName: "CarbEntryStored")
    }

    @NSManaged var carbs: Double
    @NSManaged var date: Date?
    @NSManaged var fat: Double
    @NSManaged var fpuID: UUID?
    @NSManaged var id: UUID?
    @NSManaged var isFPU: Bool
    @NSManaged var isUploadedToNS: Bool
    @NSManaged var isUploadedToHealth: Bool
    @NSManaged var isUploadedToTidepool: Bool
    @NSManaged var note: String?
    @NSManaged var protein: Double
}

extension CarbEntryStored: Identifiable {}
