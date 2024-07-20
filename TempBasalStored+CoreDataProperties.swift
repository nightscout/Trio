//
//  TempBasalStored+CoreDataProperties.swift
//  FreeAPS
//
//  Created by Cengiz Deniz on 21.07.24.
//
//

import Foundation
import CoreData


extension TempBasalStored {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<TempBasalStored> {
        return NSFetchRequest<TempBasalStored>(entityName: "TempBasalStored")
    }

    @NSManaged public var duration: Int16
    @NSManaged public var rate: NSDecimalNumber?
    @NSManaged public var tempType: String?
    @NSManaged public var pumpEvent: PumpEventStored?

}

extension TempBasalStored : Identifiable {

}
