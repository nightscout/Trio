// Trio
// PumpEventStored+CoreDataProperties.swift
// Created by polscm32 on 2024-05-05.

import CoreData
import Foundation

public extension PumpEventStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<PumpEventStored> {
        NSFetchRequest<PumpEventStored>(entityName: "PumpEventStored")
    }

    @NSManaged var id: String?
    @NSManaged var isUploadedToNS: Bool
    @NSManaged var isUploadedToHealth: Bool
    @NSManaged var isUploadedToTidepool: Bool
    @NSManaged var note: String?
    @NSManaged var timestamp: Date?
    @NSManaged var type: String?
    @NSManaged var bolus: BolusStored?
    @NSManaged var tempBasal: TempBasalStored?
}

extension PumpEventStored: Identifiable {}
