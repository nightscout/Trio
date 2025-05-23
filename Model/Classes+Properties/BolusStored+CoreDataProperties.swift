// Trio
// BolusStored+CoreDataProperties.swift
// Created by polscm32 on 2024-05-05.

import CoreData
import Foundation

public extension BolusStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<BolusStored> {
        NSFetchRequest<BolusStored>(entityName: "BolusStored")
    }

    @NSManaged var amount: NSDecimalNumber?
    @NSManaged var isExternal: Bool
    @NSManaged var isSMB: Bool
    @NSManaged var pumpEvent: PumpEventStored?
}

extension BolusStored: Identifiable {}
