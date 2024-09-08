//
//  PumpEventStored+CoreDataProperties.swift
//  FreeAPS
//
//  Created by Cengiz Deniz on 08.09.24.
//
//

import Foundation
import CoreData


extension PumpEventStored {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PumpEventStored> {
        return NSFetchRequest<PumpEventStored>(entityName: "PumpEventStored")
    }

    @NSManaged public var id: String?
    @NSManaged public var isUploadedToNS: Bool
    @NSManaged public var note: String?
    @NSManaged public var timestamp: Date?
    @NSManaged public var type: String?
    @NSManaged public var bolus: BolusStored?
    @NSManaged public var tempBasal: TempBasalStored?

}

extension PumpEventStored : Identifiable {

}
