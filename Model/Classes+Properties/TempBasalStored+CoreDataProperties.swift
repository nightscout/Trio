// Trio
// TempBasalStored+CoreDataProperties.swift
// Created by polscm32 on 2024-05-05.

import CoreData
import Foundation

public extension TempBasalStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<TempBasalStored> {
        NSFetchRequest<TempBasalStored>(entityName: "TempBasalStored")
    }

    @NSManaged var duration: Int16
    @NSManaged var rate: NSDecimalNumber?
    @NSManaged var tempType: String?
    @NSManaged var pumpEvent: PumpEventStored?
}

extension TempBasalStored: Identifiable {}
