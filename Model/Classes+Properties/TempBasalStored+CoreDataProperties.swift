//
// Trio
// TempBasalStored+CoreDataProperties.swift
// Created by Deniz Cengiz on 2024-09-11.
// Last edited by Deniz Cengiz on 2024-09-11.
// Most contributions by Deniz Cengiz and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

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
