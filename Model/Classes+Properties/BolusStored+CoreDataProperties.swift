//
// Trio
// BolusStored+CoreDataProperties.swift
// Created by Deniz Cengiz on 2024-09-11.
// Last edited by Deniz Cengiz on 2024-09-11.
// Most contributions by Deniz Cengiz and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

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
