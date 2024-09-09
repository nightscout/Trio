//
//  BolusStored+CoreDataProperties.swift
//  FreeAPS
//
//  Created by Cengiz Deniz on 08.09.24.
//
//

import Foundation
import CoreData


extension BolusStored {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<BolusStored> {
        return NSFetchRequest<BolusStored>(entityName: "BolusStored")
    }

    @NSManaged public var amount: NSDecimalNumber?
    @NSManaged public var isExternal: Bool
    @NSManaged public var isSMB: Bool
    @NSManaged public var pumpEvent: PumpEventStored?

}

extension BolusStored : Identifiable {

}
